import Foundation
import AtticModels

/// Disc games as CHD: one compressed, lossless file per disc instead of a
/// .cue with its .bin tracks (or a .gdi, or an .iso), made with MAME's
/// `chdman`, checked, and only then put in place of the originals.
public enum CHDConversion {
    /// Systems whose emulators all read CHD.
    public static let systems: Set<CanonicalSystemID> = [
        .psx, .ps2, .saturn, .segacd, .dreamcast, .pcenginecd, .threedo, .neogeocd, .pcfx,
    ]

    public struct Candidate: Sendable, Equatable {
        /// The .cue, .gdi or .iso.
        public let source: URL
        /// It and the tracks it names.
        public let files: [URL]
        public let isDVD: Bool
        public var destination: URL { source.deletingPathExtension().appendingPathExtension("chd") }
    }

    /// The disc games in a system folder that aren't CHD yet.
    public static func candidates(in folder: URL, system: CanonicalSystemID) -> [Candidate] {
        guard systems.contains(system.baseSystem) else { return [] }
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.compactMap { file in
            let ext = file.pathExtension.lowercased()
            let destination = file.deletingPathExtension().appendingPathExtension("chd")
            guard !FileManager.default.fileExists(atPath: destination.path) else { return nil }
            switch ext {
            case "cue", "gdi":
                let tracks = tracks(of: file)
                // A sheet whose tracks aren't all there can't be converted.
                guard !tracks.isEmpty, tracks.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
                return Candidate(source: file, files: [file] + tracks, isDVD: false)
            case "iso" where system.baseSystem == .ps2:
                return Candidate(source: file, files: [file], isDVD: true)
            case "iso" where system.baseSystem == .psx || system.baseSystem == .threedo:
                return Candidate(source: file, files: [file], isDVD: false)
            default:
                return nil
            }
        }
    }

    /// The track files a .cue or .gdi names, beside it.
    static func tracks(of sheet: URL) -> [URL] {
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
        guard run(chdman, [command, "-i", candidate.source.path, "-o", partial.path]),
              run(chdman, ["verify", "-i", partial.path]),
              (try? fileManager.moveItem(at: partial, to: candidate.destination)) != nil else {
            try? fileManager.removeItem(at: partial)
            return false
        }
        for file in candidate.files {
            try? fileManager.trashItem(at: file, resultingItemURL: nil)
        }
        repointPlaylists(in: candidate.source.deletingLastPathComponent(), from: candidate.source.lastPathComponent, to: candidate.destination.lastPathComponent)
        return true
    }

    static func repointPlaylists(in folder: URL, from old: String, to new: String) {
        let playlists = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "m3u" }
        for playlist in playlists {
            guard let text = try? String(contentsOf: playlist, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n").map { line in
                line.trimmingCharacters(in: .whitespaces) == old ? new : line
            }
            let updated = lines.joined(separator: "\n")
            if updated != text { try? updated.write(to: playlist, atomically: true, encoding: .utf8) }
        }
    }

    private static func run(_ executable: URL, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationReason == .exit && process.terminationStatus == 0
    }
}
