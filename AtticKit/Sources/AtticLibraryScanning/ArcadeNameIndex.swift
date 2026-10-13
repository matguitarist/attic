import Foundation
import AtticModels

/// Real titles for arcade romsets, so `mslug.zip` shows up as "Metal Slug -
/// Super Vehicle-001" instead of "mslug" before (or without) scraping.
///
/// Built from FinalBurn Neo's own Arcade DAT (ClrMamePro XML), which covers
/// every set the core runs — Neo Geo, CPS-1/2/3 and the rest — keyed by the
/// same romset names arcade ROM files use; and, for the boards FinalBurn
/// Neo doesn't run (NAOMI, Model 2, ST-V…), from ES-DE's list of every
/// MAME set's name. Each is boiled down to a small JSON cache once and
/// refreshed occasionally.
public struct ArcadeNameIndex: Sendable, Codable, Equatable {
    public struct Entry: Sendable, Codable, Equatable {
        public let title: String
        public let year: Int?
        public let manufacturer: String?
    }

    public static let datURL = URL(string: "https://raw.githubusercontent.com/libretro/FBNeo/master/dats/FinalBurn%20Neo%20(ClrMame%20Pro%20XML%2C%20Arcade%20only).dat")!
    /// ES-DE's names for every MAME set (`<mamename>`, `<realname>`),
    /// generated from MAME's own driver list.
    public static let mameNamesURL = URL(string: "https://gitlab.com/es-de/emulationstation-de/-/raw/master/resources/MAME/mamenames.xml")!

    public let entries: [String: Entry]

    public init(entries: [String: Entry]) {
        self.entries = entries
    }

    public subscript(romset: String) -> Entry? { entries[romset.lowercased()] }

    /// This index, with `other`'s sets that it doesn't have.
    public func adding(_ other: ArcadeNameIndex) -> ArcadeNameIndex {
        ArcadeNameIndex(entries: entries.merging(other.entries) { mine, _ in mine })
    }

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
                videoURL: game.videoURL,
                history: game.history
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
    /// `<description>`, `<year>` and `<manufacturer>` children; or ES-DE's
    /// MAME names: `<game>` with `<mamename>` and `<realname>`.
    public static func parse(dat data: Data) -> ArcadeNameIndex? {
        // ES-DE's list is a run of <game> elements with no root around
        // them, which XML doesn't allow: given one, it reads.
        parsed(data) ?? parsed(Data("<games>".utf8) + data + Data("</games>".utf8))
    }

    private static func parsed(_ data: Data) -> ArcadeNameIndex? {
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

        private var inGame = false
        private var mameName = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch elementName {
            case "game", "machine":
                inGame = true
                currentName = attributes["name"]?.lowercased()
                gameDescription = ""; year = ""; manufacturer = ""; mameName = ""
            case "description", "year", "manufacturer", "realname", "mamename":
                currentElement = inGame ? elementName : nil
            default:
                currentElement = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch currentElement {
            case "description", "realname": gameDescription += string
            case "mamename": mameName += string
            case "year": year += string
            case "manufacturer": manufacturer += string
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if elementName == "mamename" {
                currentName = mameName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            if elementName == "game" || elementName == "machine" { inGame = false }
            if elementName == "game" || elementName == "machine", let name = currentName, !name.isEmpty {
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

    /// The indexes cached at `urls`, earlier ones first, without fetching.
    public static func cached(at urls: [URL]) -> ArcadeNameIndex? {
        urls.compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(ArcadeNameIndex.self, from: $0) } }
            .reduce(nil) { merged, next in merged.map { $0.adding(next) } ?? next }
    }

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
