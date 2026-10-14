import Foundation
import AtticModels

/// What another front-end (RetroBat, Batocera, EmulationStation) keeps
/// for its games: its gamelists' text and the media files they name, read
/// to fill in what Attic's games lack.
///
///     roms/nes/gamelist.xml
///     roms/nes/images/1942 (Japan, USA) (En)-thumb.png    <thumbnail>: the box
///     roms/nes/images/1942 (Japan, USA) (En)-image.png    <image>: a screenshot
///     roms/nes/videos/1942 (Japan, USA) (En)-video.mp4
///     roms/nes/manuals/1942 (Japan, USA) (En)-manual.pdf
public enum FrontEndMedia {
    public struct Entry: Sendable, Equatable {
        /// The game's file (or folder), when it's there, and its path in
        /// the system's folder ("Game.zip", "Sub/Game.cue").
        public var game: URL?
        public var relativePath = ""
        /// Roughly the room the game takes: its file and those named like
        /// it beside it (a .cue's tracks, an arcade set's disc folder).
        public var bytes: Int64 = 0
        public var description: String?
        public var developer: String?
        public var publisher: String?
        public var genre: String?
        public var players: String?
        public var releaseDate: Date?
        public var rating: Double?
        public var cover: URL?
        public var screenshot: URL?
        public var video: URL?
        public var manual: URL?
    }

    /// A system's folder in the other front-end, with its entries by the
    /// game's file name without extension, lowercased.
    public struct SystemFolder: Sendable {
        public let system: CanonicalSystemID
        public let folder: URL
        public let entries: [String: Entry]
    }

    /// The systems in `folder`: itself, when it has a gamelist (one
    /// system's folder), else each folder in it that has one, named as
    /// Batocera or ES-DE name systems.
    /// Only the `wanted` systems' gamelists are read, when given.
    public static func systems(in folder: URL, wanted: Set<CanonicalSystemID>? = nil,
                               progress: (_ fraction: Double, _ folder: String) -> Void = { _, _ in }) -> [SystemFolder] {
        let manager = FileManager.default
        let candidates = manager.fileExists(atPath: folder.appending(path: "gamelist.xml").path)
            ? [folder]
            : ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
        return candidates.enumerated().compactMap { index, systemFolder in
            progress(Double(index) / Double(candidates.count), systemFolder.lastPathComponent)
            guard let definition = SystemTaxonomy.system(forShortName: systemFolder.lastPathComponent.lowercased()),
                  wanted?.contains(definition.canonicalID) ?? true,
                  let data = try? Data(contentsOf: systemFolder.appending(path: "gamelist.xml")),
                  let games = try? GamelistXMLFieldParser().parse(data) else { return nil }
            let files = FolderListing()
            var entries: [String: Entry] = [:]
            for fields in games {
                guard let path = fields["path"], !path.isEmpty else { continue }
                let stem = key(for: path)
                guard entries[stem] == nil else { continue }
                var entry = entry(fields, in: systemFolder, exists: files.contains)
                let relative = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
                var game = path.hasPrefix("/") ? URL(fileURLWithPath: path) : systemFolder.appending(path: relative)
                // Recompressed since the gamelist was written (.z64 to .7z,
                // .cso to .chd): the file named like it in a format the
                // system takes.
                if !files.contains(game), let other = files.sameName(as: game, extensions: SystemROMExtensions.extensions(for: definition.canonicalID)) {
                    game = other
                }
                if files.contains(game) {
                    entry.game = game
                    entry.relativePath = path.hasPrefix("/") ? game.lastPathComponent
                        : ((relative as NSString).deletingLastPathComponent as NSString).appendingPathComponent(game.lastPathComponent)
                    entry.bytes = files.bytes(ofGame: game)
                }
                entries[stem] = entry
            }
            return entries.isEmpty ? nil : SystemFolder(system: definition.canonicalID, folder: systemFolder, entries: entries)
        }
        .sorted { $0.folder.lastPathComponent < $1.folder.lastPathComponent }
    }

    /// How a game is looked up: its file name without extension,
    /// lowercased ("./1942 (Japan, USA) (En).zip" → "1942 (japan, usa) (en)").
    public static func key(for path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
    }

    // MARK: - Games

    /// A game's files: itself (a folder whole), a .cue's or .gdi's tracks,
    /// a playlist's discs, a .ccd's image, and an arcade set's folder of
    /// disc images named like it.
    public static func files(ofGame url: URL) -> [URL] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue { return [url] }
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var files = [url]
        switch url.pathExtension.lowercased() {
        case "cue", "gdi", "m3u":
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
            for name in referencedFiles(in: text, playlist: url.pathExtension.lowercased() == "m3u", sheet: url.pathExtension.lowercased() == "cue") {
                let file = folder.appending(path: name)
                guard manager.fileExists(atPath: file.path), !files.contains(file) else { continue }
                // A playlist's disc brings its own tracks.
                files += ["cue", "gdi"].contains(file.pathExtension.lowercased()) ? Self.files(ofGame: file) : [file]
            }
        case "ccd":
            files += ["img", "sub"].map { folder.appending(path: "\(stem).\($0)") }.filter { manager.fileExists(atPath: $0.path) }
        default:
            // An arcade set's disc images, in a folder named like it.
            let discs = folder.appending(path: stem, directoryHint: .isDirectory)
            var isFolder: ObjCBool = false
            if manager.fileExists(atPath: discs.path, isDirectory: &isFolder), isFolder.boolValue { files.append(discs) }
        }
        var seen = Set<URL>()
        return files.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    /// The files a cue sheet (FILE "x.bin" BINARY), a GDI (track lines'
    /// fifth field) or a playlist (one per line) names.
    static func referencedFiles(in text: String, playlist: Bool, sheet: Bool) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if playlist { return line.isEmpty || line.hasPrefix("#") ? nil : line }
            if sheet {
                guard line.uppercased().hasPrefix("FILE") else { return nil }
                if let quoted = line.firstMatch(of: #/"([^"]+)"/#) { return String(quoted.output.1) }
                let parts = line.split(separator: " ")
                return parts.count >= 2 ? String(parts[1]) : nil
            }
            // GDI: "1 0 4 2352 track01.raw 0", the name maybe quoted.
            if let quoted = line.firstMatch(of: #/"([^"]+)"/#) { return String(quoted.output.1) }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            return parts.count >= 6 ? String(parts[4]) : nil
        }
    }

    /// Copies a game (`files(ofGame:)`) from the other front-end's system
    /// folder into `destination`, keeping each file's place in it; files
    /// already there are left. Never moves: the other front-end keeps its
    /// games. Returns the game's place there, when its file is.
    public static func copyGame(_ url: URL, from systemFolder: URL, to destination: URL) -> URL? {
        let manager = FileManager.default
        let root = systemFolder.standardizedFileURL.path + "/"
        var lead: URL?
        for file in files(ofGame: url) {
            let path = file.standardizedFileURL.path
            let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : file.lastPathComponent
            let target = destination.appending(path: relative)
            if !manager.fileExists(atPath: target.path) {
                try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? manager.copyItem(at: file, to: target)) != nil else { continue }
            }
            if file == url { lead = target }
        }
        return lead
    }

    static func bytes(under folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    static func entry(_ fields: [String: String], in folder: URL, exists: (URL) -> Bool) -> Entry {
        func text(_ tag: String) -> String? {
            fields[tag].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        /// A media path, when its file is there: "./images/x.png" is
        /// beside the gamelist.
        func file(_ tags: [String]) -> URL? {
            for tag in tags {
                guard let path = text(tag) else { continue }
                let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                    : folder.appending(path: path.hasPrefix("./") ? String(path.dropFirst(2)) : path)
                if exists(url) { return url }
            }
            return nil
        }
        return Entry(
            description: text("desc"),
            developer: text("developer"),
            publisher: text("publisher"),
            genre: text("genre"),
            players: text("players"),
            releaseDate: GamelistDateParsing.parseReleaseDate(text("releasedate")),
            rating: text("rating").flatMap(Double.init).flatMap { $0 > 0 ? min($0, 1) : nil },
            // RetroBat's thumbnail is the box; Batocera's boxart too.
            cover: file(["thumbnail", "boxart", "cover"]),
            screenshot: file(["screenshot", "image", "titleshot"]),
            video: file(["video"]),
            manual: file(["manual"])
        )
    }
}

/// Whether files are there, and their sizes, from one listing of each
/// folder: a gamelist names thousands of media files, often on an external
/// drive.
private final class FolderListing {
    private struct File {
        let name: String
        let bytes: Int64
        let isDirectory: Bool
    }

    /// By lowercased name: the drives these are on rarely tell case apart
    /// ("mok-image.PNG").
    private var listings: [String: [String: File]] = [:]

    private func listing(_ folder: URL) -> [String: File] {
        if let listing = listings[folder.path] { return listing }
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        var listing: [String: File] = [:]
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            listing[url.lastPathComponent.lowercased()] = File(name: url.lastPathComponent, bytes: Int64(values?.fileSize ?? 0),
                                                               isDirectory: values?.isDirectory == true)
        }
        listings[folder.path] = listing
        return listing
    }

    func contains(_ url: URL) -> Bool {
        listing(url.deletingLastPathComponent())[url.lastPathComponent.lowercased()] != nil
    }

    /// Another file of the same name, in one of `extensions`.
    func sameName(as url: URL, extensions: Set<String>?) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let folder = url.deletingLastPathComponent()
        return listing(folder).values
            .filter { !$0.isDirectory && ($0.name as NSString).deletingPathExtension.lowercased() == stem
                && extensions?.contains(($0.name as NSString).pathExtension.lowercased()) ?? true }
            .map { folder.appending(path: $0.name) }
            .min { $0.lastPathComponent < $1.lastPathComponent }
    }

    func bytes(ofGame url: URL) -> Int64 {
        let listing = listing(url.deletingLastPathComponent())
        guard let file = listing[url.lastPathComponent.lowercased()] else { return 0 }
        if file.isDirectory { return FrontEndMedia.bytes(under: url) }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return listing.values.filter { $0.name.lowercased().hasPrefix(stem) }.reduce(0) { total, other in
            total + (other.isDirectory ? FrontEndMedia.bytes(under: url.deletingLastPathComponent().appending(path: other.name)) : other.bytes)
        }
    }
}
