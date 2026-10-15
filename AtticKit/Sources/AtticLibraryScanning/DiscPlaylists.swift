import Foundation
import AtticModels

/// Multi-disc games as one game: a `.m3u` playlist naming each disc's file,
/// which emulators use to swap discs, while the discs themselves stay out
/// of the library. `Final Fantasy VII (USA) (Disc 1).chd`, `(Disc 2)`…
/// become `Final Fantasy VII (USA).m3u`.
///
/// Discs can sit in a folder of their own beside the playlist, as RetroBat
/// keeps them (`Game (MultiDisc).m3u` listing `\MultiDisc\Game (Disc 1).chd`):
/// Windows' paths read as macOS's (see `partName`).
public enum DiscPlaylists {
    public struct Playlist: Sendable, Equatable {
        public let url: URL
        public let discs: [URL]
    }

    /// Each disc's file to list, best first: a `.cue` names its `.bin`
    /// tracks, which aren't listed themselves.
    static let discExtensions = ["chd", "cue", "gdi", "ccd", "iso", "pbp", "cdi", "img"]

    /// Disc sets in `folder`, or in a folder in it (RetroBat's
    /// `MultiDisc`), that no playlist lists yet. Their playlists go in
    /// `folder`.
    public static func missing(in folder: URL) -> [Playlist] {
        let manager = FileManager.default
        let top = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let existing = Set(top.filter { $0.pathExtension.lowercased() == "m3u" }.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        let listed = listedFiles(in: folder)
        let subfolders = top.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && !ImportedMedia.nonGameFolderNames.contains($0.lastPathComponent.lowercased())
        }
        let files = top + subfolders.flatMap { (try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] }

        // Folder and title (without the disc tag) → disc number → that disc's files.
        var sets: [String: [Int: [URL]]] = [:]
        for file in files where discExtensions.contains(file.pathExtension.lowercased()) {
            guard !listed.contains(relativePath(of: file, in: folder)),
                  let (title, number) = disc(in: file.deletingPathExtension().lastPathComponent) else { continue }
            sets[file.deletingLastPathComponent().path + "/" + title, default: [:]][number, default: []].append(file)
        }
        return sets.compactMap { key, discs in
            let title = (key as NSString).lastPathComponent
            guard discs.count > 1, !existing.contains(title.lowercased()) else { return nil }
            let chosen = discs.keys.sorted().compactMap { number in
                discs[number]?.min { rank($0) < rank($1) }
            }
            return Playlist(url: folder.appending(path: "\(title).m3u"), discs: chosen)
        }
        .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// `file`'s path in `folder` ("MultiDisc/Game (Disc 1).chd"), or its
    /// name when it's elsewhere.
    public static func relativePath(of file: URL, in folder: URL) -> String {
        let root = folder.standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : file.lastPathComponent
    }

    /// Writes the playlist, and gives the game disc 1's media where it has
    /// none of its own. Returns whether it was written.
    @discardableResult
    public static func create(_ playlist: Playlist, systemFolder: URL) -> Bool {
        let folder = playlist.url.deletingLastPathComponent()
        let text = playlist.discs.map { relativePath(of: $0, in: folder) }.joined(separator: "\n") + "\n"
        guard (try? text.write(to: playlist.url, atomically: true, encoding: .utf8)) != nil else { return false }
        if let first = playlist.discs.first {
            for kind in MediaKind.allCases {
                let from = MediaFolder.baseURL(forSystemFolder: systemFolder, romRelativePath: relativePath(of: first, in: systemFolder), kind: kind)
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
            for name in parts(of: sheet) {
                listed.insert(name)
                // A disc in a folder of its own (RetroBat's MultiDisc) is
                // a cue sheet whose tracks are beside it, there.
                let ext = (name as NSString).pathExtension.lowercased()
                let directory = (name as NSString).deletingLastPathComponent
                guard sheet.pathExtension.lowercased() == "m3u", ["cue", "gdi"].contains(ext), !directory.isEmpty else { continue }
                for track in parts(of: folder.appending(path: name)) {
                    listed.insert((directory as NSString).appendingPathComponent(track))
                }
            }
        }
        return listed
    }

    /// The files a playlist or sheet names, as paths beside it.
    public static func parts(of sheet: URL) -> [String] {
        guard let text = text(of: sheet) else { return [] }
        let type = sheet.pathExtension.lowercased()
        return text.split(whereSeparator: \.isNewline).compactMap { partName($0.trimmingCharacters(in: .whitespaces), in: type) }
    }

    static func text(of url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
    }

    /// A playlist's text as macOS emulators read it: forward slashes and
    /// plain line ends, or nil when it already is. Playlists made on
    /// Windows (RetroBat's) name `\MultiDisc\Game (Disc 1).chd`, which
    /// an emulator here takes for one odd file name.
    public static func macText(of text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { raw -> String in
            let line = raw.trimmingCharacters(in: .whitespaces)
            return partName(line, in: "m3u") ?? line
        }
        let rewritten = lines.joined(separator: "\n") + "\n"
        return rewritten == text ? nil : rewritten
    }

    /// The file a sheet's line names, if any. A playlist's line is read as
    /// a path beside it, whichever way its slashes lean: `\MultiDisc\x.chd`
    /// and `.\MultiDisc\x.chd` (Windows, from the playlist's folder) and
    /// `./MultiDisc/x.chd` are all `MultiDisc/x.chd`.
    static func partName(_ line: String, in sheetType: String) -> String? {
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        switch sheetType {
        case "m3u":
            var path = line
            for prefix in [".\\", "\\", "./"] where path.hasPrefix(prefix) {
                path.removeFirst(prefix.count)
                break
            }
            path = path.replacingOccurrences(of: "\\", with: "/")
            while path.hasPrefix("./") { path.removeFirst(2) }
            return path.isEmpty ? nil : path
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

/// What the Disc Playlists tool finds in the ROMs folders of systems that
/// play playlists: multi-disc games without one, playlists written on
/// Windows, and playlists naming discs that aren't there.
public struct DiscPlaylistPlan: Sendable {
    public struct Broken: Sendable, Equatable {
        public let playlist: URL
        /// The discs it names that aren't there, as it names them.
        public let absent: [String]
    }

    public var missing: [DiscPlaylists.Playlist] = []
    /// To rewrite with forward slashes (see `DiscPlaylists.macText`).
    public var windows: [URL] = []
    public var broken: [Broken] = []

    public var isEmpty: Bool { missing.isEmpty && windows.isEmpty && broken.isEmpty }

    public static func plan(romsRoots: [URL]) -> DiscPlaylistPlan {
        var plan = DiscPlaylistPlan()
        let manager = FileManager.default
        for root in romsRoots {
            let folders = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let system = SystemTaxonomy.system(forShortName: folder.lastPathComponent.lowercased())?.canonicalID,
                      SystemROMExtensions.extensions(for: system)?.contains("m3u") == true else { continue }
                plan.missing += DiscPlaylists.missing(in: folder)
                let playlists = ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
                    .filter { $0.pathExtension.lowercased() == "m3u" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for playlist in playlists {
                    guard let text = DiscPlaylists.text(of: playlist) else { continue }
                    if DiscPlaylists.macText(of: text) != nil { plan.windows.append(playlist) }
                    let absent = DiscPlaylists.parts(of: playlist).filter { !manager.fileExists(atPath: folder.appending(path: $0).path) }
                    if !absent.isEmpty { plan.broken.append(Broken(playlist: playlist, absent: absent)) }
                }
            }
        }
        return plan
    }

    /// Writes the missing playlists and rewrites Windows ones. Returns
    /// how many of each.
    public static func apply(_ plan: DiscPlaylistPlan) -> (created: Int, fixed: Int) {
        var created = 0
        for playlist in plan.missing where DiscPlaylists.create(playlist, systemFolder: playlist.url.deletingLastPathComponent()) {
            created += 1
        }
        var fixed = 0
        for playlist in plan.windows {
            guard let text = DiscPlaylists.text(of: playlist), let mac = DiscPlaylists.macText(of: text),
                  (try? mac.write(to: playlist, atomically: true, encoding: .utf8)) != nil else { continue }
            fixed += 1
        }
        return (created, fixed)
    }

    /// Only the chosen parts.
    public func only(creating: Bool, fixing: Bool) -> DiscPlaylistPlan {
        var plan = self
        if !creating { plan.missing = [] }
        if !fixing { plan.windows = [] }
        plan.broken = []
        return plan
    }
}
