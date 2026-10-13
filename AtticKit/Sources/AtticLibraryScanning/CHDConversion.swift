import Foundation
import AtticModels

/// Disc games as CHD: one compressed, lossless file per disc instead of a
/// .cue with its .bin tracks (or a .gdi, or an .iso), made with MAME's
/// `chdman`, checked, and only then put in place of the originals. And
/// back, for an emulator that wants the original files.
public enum CHDConversion {
    /// Systems whose emulators all read CHD.
    public static let systems: Set<CanonicalSystemID> = [
        .psx, .ps2, .psp, .saturn, .segacd, .dreamcast, .pcenginecd, .threedo, .neogeocd, .pcfx,
    ]

    public struct Candidate: Sendable, Equatable {
        /// The .cue, .gdi or .iso.
        public let source: URL
        /// It and the tracks it names.
        public let files: [URL]
        public let isDVD: Bool
        /// chdman's hunk size, when not its own: PPSSPP reads PSP CHDs
        /// made with 2048-byte hunks, one sector each, much faster.
        var hunkBytes: Int?
        public var destination: URL { source.deletingPathExtension().appendingPathExtension("chd") }
        public var bytes: Int64 { files.reduce(0) { $0 + MediaFolder.fileSize($1) } }
    }

    /// The disc games in a system folder that aren't CHD yet.
    public static func candidates(in folder: URL, system: CanonicalSystemID) -> [Candidate] {
        guard systems.contains(system.baseSystem) else { return [] }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { candidate(for: $0, system: system) }
    }

    /// `file` as a disc to convert, if it is one.
    static func candidate(for file: URL, system: CanonicalSystemID) -> Candidate? {
        guard systems.contains(system.baseSystem) else { return nil }
        let destination = file.deletingPathExtension().appendingPathExtension("chd")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return nil }
        switch file.pathExtension.lowercased() {
        case "cue", "gdi":
            let tracks = tracks(of: file)
            // A sheet whose tracks aren't all there can't be converted.
            guard !tracks.isEmpty, tracks.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
            return Candidate(source: file, files: [file] + tracks, isDVD: false)
        case "iso" where system.baseSystem == .ps2:
            return Candidate(source: file, files: [file], isDVD: true)
        case "iso" where system.baseSystem == .psp:
            return Candidate(source: file, files: [file], isDVD: true, hunkBytes: 2048)
        case "iso" where system.baseSystem == .psx || system.baseSystem == .threedo:
            return Candidate(source: file, files: [file], isDVD: false)
        default:
            return nil
        }
    }

    /// The discs of the game `url` (itself, or a playlist's discs) that
    /// can become CHD.
    public static func candidates(forGame url: URL, system: CanonicalSystemID) -> [Candidate] {
        discs(ofGame: url).compactMap { candidate(for: $0, system: system) }
    }

    /// The CHDs of the game `url` (itself, or a playlist's discs) that can
    /// be turned back into their original kind of files.
    public static func chds(forGame url: URL) -> [URL] {
        discs(ofGame: url).filter { disc in
            guard disc.pathExtension.lowercased() == "chd", let header = CHDHeader.read(disc),
                  let output = extractedFile(for: disc, kind: header.kind) else { return false }
            return !FileManager.default.fileExists(atPath: output.path)
        }
    }

    private static func discs(ofGame url: URL) -> [URL] {
        guard url.pathExtension.lowercased() == "m3u" else { return [url] }
        let folder = url.deletingLastPathComponent()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            DiscPlaylists.partName(line.trimmingCharacters(in: .whitespaces), in: "m3u").map { folder.appending(path: $0) }
        }
    }

    /// The .cue, .gdi or .iso a CHD turns back into.
    static func extractedFile(for chd: URL, kind: CHDHeader.Kind) -> URL? {
        let stem = chd.deletingPathExtension()
        switch kind {
        case .cd: return stem.appendingPathExtension("cue")
        case .gdrom: return stem.appendingPathExtension("gdi")
        case .dvd: return stem.appendingPathExtension("iso")
        case .hardDisk, .other: return nil
        }
    }

    /// The track files a .cue or .gdi names, beside it.
    public static func tracks(of sheet: URL) -> [URL] {
        guard let text = (try? String(contentsOf: sheet, encoding: .utf8)) ?? (try? String(contentsOf: sheet, encoding: .isoLatin1)) else { return [] }
        let type = sheet.pathExtension.lowercased()
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let name = DiscPlaylists.partName(line.trimmingCharacters(in: .whitespaces), in: type), seen.insert(name).inserted else { return nil }
            return sheet.deletingLastPathComponent().appending(path: name)
        }
    }

    /// Where `chdman` is: Homebrew's `rom-tools` (built from MAME's own
    /// source) puts it in its bin folder.
    public static func findCHDMan() -> URL? {
        ["/opt/homebrew/bin/chdman", "/usr/local/bin/chdman"].map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Makes the CHD, verifies it, then moves the originals to the Trash
    /// and points playlists naming the old file at the new one. A CHD
    /// that fails is removed and the originals stay.
    @discardableResult
    public static func convert(_ candidate: Candidate, chdman: URL) -> Bool {
        let fileManager = FileManager.default
        let partial = candidate.destination.deletingLastPathComponent()
            .appending(path: ".\(candidate.destination.lastPathComponent).partial")
        try? fileManager.removeItem(at: partial)
        let command = candidate.isDVD ? "createdvd" : "createcd"
        let hunk = candidate.hunkBytes.map { ["-hs", String($0)] } ?? []
        guard run(chdman, [command, "-i", candidate.source.path, "-o", partial.path] + hunk),
              run(chdman, ["verify", "-i", partial.path]),
              (try? fileManager.moveItem(at: partial, to: candidate.destination)) != nil else {
            try? fileManager.removeItem(at: partial)
            return false
        }
        for file in candidate.files {
            try? fileManager.trashItem(at: file, resultingItemURL: nil)
        }
        ReplacedGameFile.repoint(in: candidate.source.deletingLastPathComponent(), from: candidate.source.lastPathComponent, to: candidate.destination.lastPathComponent)
        return true
    }

    /// Turns a CHD back into a .cue with one .bin (a .gdi with its tracks
    /// for a Dreamcast GD-ROM, an .iso for a DVD), then moves the CHD to
    /// the Trash and points playlists at the new file. If chdman fails,
    /// what it wrote is removed and the CHD stays.
    @discardableResult
    public static func extract(_ chd: URL, chdman: URL) -> Bool {
        let fileManager = FileManager.default
        guard let header = CHDHeader.read(chd), let output = extractedFile(for: chd, kind: header.kind),
              !fileManager.fileExists(atPath: output.path) else { return false }
        let folder = chd.deletingLastPathComponent()
        var arguments = [header.kind == .dvd ? "extractdvd" : "extractcd", "-i", chd.lastPathComponent, "-o", output.lastPathComponent]
        if header.kind == .cd {
            arguments += ["-ob", output.deletingPathExtension().appendingPathExtension("bin").lastPathComponent]
        }
        let ran = run(chdman, arguments, in: folder)
        let written = [output] + (header.kind == .dvd ? [] : tracks(of: output))
        guard ran, written.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            for file in written { try? fileManager.removeItem(at: file) }
            if header.kind == .cd {
                try? fileManager.removeItem(at: output.deletingPathExtension().appendingPathExtension("bin"))
            }
            return false
        }
        try? fileManager.trashItem(at: chd, resultingItemURL: nil)
        ReplacedGameFile.repoint(in: folder, from: chd.lastPathComponent, to: output.lastPathComponent)
        return true
    }

    private static func run(_ executable: URL, _ arguments: [String], in folder: URL? = nil) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = folder
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    }
}
