import Foundation
import AtticModels

/// Multi-disc games as one game: a `.m3u` playlist naming each disc's file,
/// which emulators use to swap discs, while the discs themselves stay out
/// of the library. `Final Fantasy VII (USA) (Disc 1).chd`, `(Disc 2)`…
/// become `Final Fantasy VII (USA).m3u`.
public enum DiscPlaylists {
    public struct Playlist: Sendable, Equatable {
        public let url: URL
        public let discs: [URL]
    }

    /// Each disc's file to list, best first: a `.cue` names its `.bin`
    /// tracks, which aren't listed themselves.
    static let discExtensions = ["chd", "cue", "gdi", "ccd", "iso", "pbp", "cdi", "img"]

    /// Disc sets in `folder` that have no playlist yet.
    public static func missing(in folder: URL) -> [Playlist] {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
        let existing = Set(files.filter { $0.pathExtension.lowercased() == "m3u" }.map { $0.deletingPathExtension().lastPathComponent.lowercased() })

        // Title (without the disc tag) → disc number → that disc's files.
        var sets: [String: [Int: [URL]]] = [:]
        for file in files where discExtensions.contains(file.pathExtension.lowercased()) {
            guard let (title, number) = disc(in: file.deletingPathExtension().lastPathComponent) else { continue }
            sets[title, default: [:]][number, default: []].append(file)
        }
        return sets.compactMap { title, discs in
            guard discs.count > 1, !existing.contains(title.lowercased()) else { return nil }
            let chosen = discs.keys.sorted().compactMap { number in
                discs[number]?.min { rank($0) < rank($1) }
            }
            return Playlist(url: folder.appending(path: "\(title).m3u"), discs: chosen)
        }
        .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// Writes the playlist, and gives the game disc 1's media where it has
    /// none of its own. Returns whether it was written.
    @discardableResult
    public static func create(_ playlist: Playlist, systemFolder: URL) -> Bool {
        let text = playlist.discs.map(\.lastPathComponent).joined(separator: "\n") + "\n"
        guard (try? text.write(to: playlist.url, atomically: true, encoding: .utf8)) != nil else { return false }
        if let first = playlist.discs.first {
            for kind in MediaKind.allCases {
                let from = MediaFolder.baseURL(forSystemFolder: systemFolder, romRelativePath: first.lastPathComponent, kind: kind)
                let to = MediaFolder.baseURL(forSystemFolder: systemFolder, romRelativePath: playlist.url.lastPathComponent, kind: kind)
                guard MediaFolder.existingFiles(base: to).isEmpty,
                      let source = (MediaFolder.existingFiles(base: from) + [from.appendingPathExtension("pdf")])
                        .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { continue }
                try? FileManager.default.copyItem(at: source, to: to.appendingPathExtension(source.pathExtension))
            }
        }
        return true
    }

    /// Writes the missing playlists of every system folder whose system
    /// plays them. Returns how many.
    @discardableResult
    public static func createMissing(romsRoots: [URL]) -> Int {
        var created = 0
        for root in romsRoots {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            for folder in folders {
                guard let system = SystemTaxonomy.system(forShortName: folder.lastPathComponent.lowercased())?.canonicalID,
                      SystemROMExtensions.extensions(for: system)?.contains("m3u") == true else { continue }
                for playlist in missing(in: folder) where create(playlist, systemFolder: folder) { created += 1 }
            }
        }
        return created
    }

    /// The files other files in `folder` name as their parts, by name: the
    /// discs of `.m3u` playlists, the tracks of `.cue` and `.gdi` sheets.
    /// They're played through those, so aren't games of their own.
    public static func listedFiles(in folder: URL) -> Set<String> {
        let sheets = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { ["m3u", "cue", "gdi"].contains($0.pathExtension.lowercased()) }
        var listed = Set<String>()
        for sheet in sheets {
            guard let text = (try? String(contentsOf: sheet, encoding: .utf8)) ?? (try? String(contentsOf: sheet, encoding: .isoLatin1)) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                if let name = partName(line.trimmingCharacters(in: .whitespaces), in: sheet.pathExtension.lowercased()) {
                    listed.insert(name.hasPrefix("./") ? String(name.dropFirst(2)) : name)
                }
            }
        }
        return listed
    }

    /// The file a sheet's line names, if any.
    static func partName(_ line: String, in sheetType: String) -> String? {
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        switch sheetType {
        case "m3u":
            return line
        case "cue":
            // FILE "Game (Track 1).bin" BINARY
            return line.firstMatch(of: /^FILE\s+"([^"]+)"/.ignoresCase()).map { String($0.output.1) }
                ?? line.firstMatch(of: /^FILE\s+(\S+)/.ignoresCase()).map { String($0.output.1) }
        case "gdi":
            // 1 0 4 2352 "track01.bin" 0  (the first line is the track count)
            let fields = line.firstMatch(of: /^\d+\s+\d+\s+\d+\s+\d+\s+(?:"([^"]+)"|(\S+))/)
            return fields.flatMap { ($0.output.1 ?? $0.output.2).map(String.init) }
        default:
            return nil
        }
    }

    // MARK: - Names

    /// The title without its disc tag, and the disc's number:
    /// "Final Fantasy VII (USA) (Disc 2)" → ("Final Fantasy VII (USA)", 2).
    static func disc(in name: String) -> (String, Int)? {
        guard let match = name.firstMatch(of: /\s*\((?:Disc|Disk|CD)\s*([0-9]+)(?:\s*of\s*[0-9]+)?\)/.ignoresCase()),
              let number = Int(match.output.1) else { return nil }
        var title = name
        title.removeSubrange(match.range)
        return (title.trimmingCharacters(in: .whitespaces), number)
    }

    private static func rank(_ url: URL) -> Int {
        discExtensions.firstIndex(of: url.pathExtension.lowercased()) ?? discExtensions.count
    }
}
