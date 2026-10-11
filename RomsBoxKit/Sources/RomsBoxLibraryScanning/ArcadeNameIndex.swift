import Foundation
import RomsBoxModels

/// Real titles for arcade romsets, so `mslug.zip` shows up as "Metal Slug -
/// Super Vehicle-001" instead of "mslug" before (or without) scraping.
///
/// Built from FinalBurn Neo's own Arcade DAT (ClrMamePro XML), which covers
/// every set the core runs — Neo Geo, CPS-1/2/3 and the rest — keyed by the
/// same romset names arcade ROM files use. The 14 MB DAT is boiled down to
/// a small JSON cache once and refreshed occasionally.
public struct ArcadeNameIndex: Sendable, Codable, Equatable {
    public struct Entry: Sendable, Codable, Equatable {
        public let title: String
        public let year: Int?
        public let manufacturer: String?
    }

    public static let datURL = URL(string: "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/FinalBurn%20Neo%20(ClrMame%20Pro%20XML%2C%20Arcade%20only).dat")!

    public let entries: [String: Entry]

    public init(entries: [String: Entry]) {
        self.entries = entries
    }

    public subscript(romset: String) -> Entry? { entries[romset.lowercased()] }

    // MARK: - Applying

    /// Fills in names for games the importer could only name after their
    /// file — titles from a gamelist.xml are left as they are. Developer
    /// and release year are only filled when missing.
    public func applying(to system: ImportedSystemData) -> ImportedSystemData {
        let games = system.games.map { game -> ImportedGameRecord in
            let romset = ((game.romRelativePath as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let entry = self[romset],
                  game.title == ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: game.romRelativePath) else { return game }
            return ImportedGameRecord(
                romRelativePath: game.romRelativePath,
                title: entry.title,
                sortTitle: game.sortTitle,
                description: game.description,
                releaseDate: game.releaseDate ?? entry.year.flatMap(Self.firstOfYear),
                developer: game.developer ?? entry.manufacturer,
                publisher: game.publisher,
                genre: game.genre,
                players: game.players,
                rating: game.rating,
                favorite: game.favorite,
                coverArtURL: game.coverArtURL,
                titleScreenURL: game.titleScreenURL,
                videoURL: game.videoURL
            )
        }
        return ImportedSystemData(
            canonicalID: system.canonicalID,
            libraryFormat: system.libraryFormat,
            romsRootURL: system.romsRootURL,
            games: games
        )
    }

    private static func firstOfYear(_ year: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1))
    }

    // MARK: - Parsing

    /// Parses a ClrMamePro/Logiqx XML DAT: `<game name="…">` with
    /// `<description>`, `<year>` and `<manufacturer>` children.
    public static func parse(dat data: Data) -> ArcadeNameIndex? {
        let delegate = DATParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // The DAT declares an external DTD; never fetch it.
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.entries.isEmpty else { return nil }
        return ArcadeNameIndex(entries: delegate.entries)
    }

    /// FinalBurn Neo tells sets of the same game apart with trailing tags —
    /// "(World 900227)", "(NGM-056)", "(set 1)" — which are noise in a
    /// library with one file per game, so every trailing tag is dropped
    /// (unless that would leave nothing).
    static func cleanedTitle(_ description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed
            .replacing(#/(\s*[\(\[][^\(\)\[\]]*[\)\]])+$/#, with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? trimmed : stripped
    }

    private final class DATParserDelegate: NSObject, XMLParserDelegate {
        var entries: [String: Entry] = [:]
        private var currentName: String?
        private var gameDescription = ""
        private var year = ""
        private var manufacturer = ""
        private var currentElement: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch elementName {
            case "game", "machine":
                currentName = attributes["name"]?.lowercased()
                gameDescription = ""; year = ""; manufacturer = ""
            case "description", "year", "manufacturer":
                currentElement = currentName == nil ? nil : elementName
            default:
                currentElement = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch currentElement {
            case "description": gameDescription += string
            case "year": year += string
            case "manufacturer": manufacturer += string
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if elementName == "game" || elementName == "machine", let name = currentName {
                let title = ArcadeNameIndex.cleanedTitle(gameDescription)
                if !title.isEmpty {
                    let manufacturer = manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
                    entries[name] = Entry(
                        title: title,
                        year: Int(year.trimmingCharacters(in: .whitespacesAndNewlines)),
                        manufacturer: manufacturer.isEmpty ? nil : manufacturer
                    )
                }
                currentName = nil
            }
            currentElement = nil
        }
    }

    // MARK: - Caching

    /// The cached index when it's fresh enough; otherwise fetches the DAT,
    /// rebuilds the cache, and returns that. Falls back to a stale cache
    /// (or `nil`) when the fetch fails, so an offline scan still works.
    public static func load(
        cacheURL: URL,
        maxAge: TimeInterval = 30 * 24 * 60 * 60,
        fetchDAT: @Sendable () async throws -> Data
    ) async -> ArcadeNameIndex? {
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(ArcadeNameIndex.self, from: $0) }
        let modified = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached, let modified, Date.now.timeIntervalSince(modified) < maxAge {
            return cached
        }
        guard let data = try? await fetchDAT(), let fresh = parse(dat: data) else { return cached }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(fresh).write(to: cacheURL, options: .atomic)
        return fresh
    }
}
