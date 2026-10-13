import Foundation

/// A collection as a file: `collection.json` in its folder
/// (`Emulation/Collections/<Name>/`, beside its `logo` and `artwork`),
/// which is also what's exported and imported. Games are named by system
/// and path in the system's ROMs folder, with their title to find them
/// again in a library laid out differently.
public struct CollectionFile: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var system: String
        public var path: String
        public var title: String

        public init(system: String, path: String, title: String) {
            self.system = system
            self.path = path
            self.title = title
        }

        public var key: String { "\(system)/\(path)" }
    }

    /// Bumped if the layout ever changes incompatibly.
    public var format = 1
    public var id: UUID
    public var name: String
    public var including: String
    public var excluding: String
    public var system: String?
    public var addsMatchingGames: Bool
    public var games: [Entry]
    /// Games the search must never add (see `GameCollection.excludedGameKeys`).
    public var excluded: [String]
    /// The rest of the search, left out when unset (and in files from
    /// before it).
    public var genres: String?
    public var minPlayers: Int?
    public var fromYear: Int?
    public var toYear: Int?
    public var favoritesOnly: Bool?

    /// The search the file describes.
    public var search: CollectionSearch {
        CollectionSearch(including: including, excluding: excluding, genres: genres ?? "", minPlayers: minPlayers ?? 0,
                         fromYear: fromYear ?? 0, toYear: toYear ?? 0, favoritesOnly: favoritesOnly ?? false)
    }

    /// Sets the search's parts beyond the title.
    public mutating func setCriteria(from search: CollectionSearch) {
        genres = search.genres.isEmpty ? nil : search.genres
        minPlayers = search.minPlayers > 1 ? search.minPlayers : nil
        fromYear = search.fromYear > 0 ? search.fromYear : nil
        toYear = search.toYear > 0 ? search.toYear : nil
        favoritesOnly = search.favoritesOnly ? true : nil
    }

    public init(id: UUID, name: String, including: String = "", excluding: String = "", system: String? = nil,
                addsMatchingGames: Bool = false, games: [Entry] = [], excluded: [String] = []) {
        self.id = id
        self.name = name
        self.including = including
        self.excluding = excluding
        self.system = system
        self.addsMatchingGames = addsMatchingGames
        self.games = games
        self.excluded = excluded
    }

    public static let fileName = "collection.json"
    /// The collection's own pictures, beside `collection.json`.
    public static let logoName = "logo"
    public static let artworkName = "artwork"

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> CollectionFile {
        try JSONDecoder().decode(CollectionFile.self, from: data)
    }

    /// A folder name for `name`: without the characters the Finder or
    /// other systems can't take.
    public static func folderName(for name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/:\\\\?*\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Collection" : cleaned
    }
}
