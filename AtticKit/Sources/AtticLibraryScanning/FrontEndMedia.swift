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
    public static func systems(in folder: URL, wanted: Set<CanonicalSystemID>? = nil) -> [SystemFolder] {
        let manager = FileManager.default
        let candidates = manager.fileExists(atPath: folder.appending(path: "gamelist.xml").path)
            ? [folder]
            : ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
        return candidates.compactMap { systemFolder in
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
                entries[stem] = entry(fields, in: systemFolder, exists: files.contains)
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

/// Whether files are there, from one listing of each folder: a gamelist
/// names thousands of media files, often on an external drive.
private final class FolderListing {
    private var listings: [String: Set<String>] = [:]

    func contains(_ url: URL) -> Bool {
        let folder = url.deletingLastPathComponent().path
        if listings[folder] == nil {
            // Lowercased: the drives these are on rarely tell case apart
            // ("mok-image.PNG").
            listings[folder] = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).map { $0.lowercased() })
        }
        return listings[folder]?.contains(url.lastPathComponent.lowercased()) == true
    }
}
