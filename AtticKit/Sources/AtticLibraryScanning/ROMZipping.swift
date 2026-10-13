import Foundation
import AtticModels

/// Cartridge games zipped: each ROM in a .zip of its own, with macOS's
/// `zip`. Attic unzips a game when it starts (see `ZippedROMExtractor`),
/// with the same name, so its saves and media still match.
///
/// Only cartridge systems: a disc game is a CHD's job, and arcade, DOS or
/// computer zips hold whole sets the emulator reads as they are.
public enum ROMZipping {
    public static let systems: Set<CanonicalSystemID> = [
        .nes, .fds, .snes, .gb, .gbc, .gba, .n64, .nds, .virtualboy, .pokemini,
        .genesis, .sega32x, .mastersystem, .gamegear, .sg1000,
        .pcengine, .supergrafx, .atari2600, .atari5200, .atari7800, .atarilynx,
        .wonderswan, .wonderswancolor, .ngp, .ngpc,
        .colecovision, .intellivision, .vectrex, .odyssey2, .channelf,
    ]

    /// Files that aren't a cartridge on their own.
    static let skippedExtensions: Set<String> = [
        "zip", "7z", "chd", "cue", "gdi", "iso", "img", "ccd", "toc", "sub", "cdi", "m3u",
    ]
    /// Marks a ROM that didn't get smaller zipped, so it isn't offered again.
    static let checkedAttribute = "com.attic.zip-checked"
    /// A zip has to save at least this much to replace the ROM.
    static let keptRatio = 0.9

    /// The ROMs in a system folder that could be zipped.
    public static func candidates(in folder: URL, system: CanonicalSystemID) -> [URL] {
        guard systems.contains(system.baseSystem),
              let extensions = SystemROMExtensions.extensions(for: system.baseSystem) else { return [] }
        let fileManager = FileManager.default
        let files = ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? [])
        let listed = DiscPlaylists.listedFiles(in: folder)
        let stems = Set(files.filter { ["zip", "7z"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        return files.filter { file in
            let ext = file.pathExtension.lowercased()
            return extensions.contains(ext) && !skippedExtensions.contains(ext)
                && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && !listed.contains(file.lastPathComponent)
                && !stems.contains(file.deletingPathExtension().lastPathComponent.lowercased())
                && getxattr(file.path, checkedAttribute, nil, 0, 0, 0) < 0
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Whether the game `rom` could be zipped.
    public static func canZip(_ rom: URL, system: CanonicalSystemID) -> Bool {
        let folder = rom.deletingLastPathComponent()
        guard systems.contains(system.baseSystem),
              let extensions = SystemROMExtensions.extensions(for: system.baseSystem) else { return false }
        let ext = rom.pathExtension.lowercased()
        return extensions.contains(ext) && !skippedExtensions.contains(ext)
            && FileManager.default.fileExists(atPath: rom.path)
            && !["zip", "7z"].contains { FileManager.default.fileExists(atPath: rom.deletingPathExtension().appendingPathExtension($0).path) }
            && !DiscPlaylists.listedFiles(in: folder).contains(rom.lastPathComponent)
            && getxattr(rom.path, checkedAttribute, nil, 0, 0, 0) < 0
    }

    /// Zips `rom` beside it, tests the zip, and when it's at least 10%
    /// smaller puts it in the ROM's place (the ROM goes to the Trash).
    /// Returns the zip, or nil when the ROM stays.
    @discardableResult
    public static func zip(_ rom: URL) -> URL? {
        let fileManager = FileManager.default
        let folder = rom.deletingLastPathComponent()
        let destination = rom.deletingPathExtension().appendingPathExtension("zip")
        let partial = folder.appending(path: ".\(destination.lastPathComponent).partial")
        try? fileManager.removeItem(at: partial)
        guard !fileManager.fileExists(atPath: destination.path),
              run("/usr/bin/zip", ["-q", "-X", "-9", "-j", partial.path, rom.path]),
              run("/usr/bin/unzip", ["-tqq", partial.path]) else {
            try? fileManager.removeItem(at: partial)
            return nil
        }
        guard Double(MediaFolder.fileSize(partial)) <= Double(MediaFolder.fileSize(rom)) * keptRatio,
              (try? fileManager.moveItem(at: partial, to: destination)) != nil else {
            try? fileManager.removeItem(at: partial)
            setxattr(rom.path, checkedAttribute, "1", 1, 0, 0)
            return nil
        }
        try? fileManager.trashItem(at: rom, resultingItemURL: nil)
        ReplacedGameFile.repoint(in: folder, from: rom.lastPathComponent, to: destination.lastPathComponent)
        return destination
    }

    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    }
}
