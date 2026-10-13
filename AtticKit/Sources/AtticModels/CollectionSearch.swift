import Foundation

/// Which games a collection gathers: titles containing any of `including`
/// (several terms, comma-separated, like "Super Mario, Mario Bros") but
/// none of `excluding` ("Tennis, Golf, Kart"), and, when set, a genre,
/// how many can play, the years they came out, and favorites only. Each
/// part left empty doesn't narrow anything, so a collection can go by
/// title, by the rest ("2-player games of the 90s"), or both. Case and
/// accents don't matter.
public struct CollectionSearch: Hashable, Sendable {
    public var including: String
    public var excluding: String
    /// Genres, comma-separated: any of them.
    public var genres: String
    /// Games for at least this many players (0 or 1: any).
    public var minPlayers: Int
    /// Released from, and up to, these years (0: no bound).
    public var fromYear: Int
    public var toYear: Int
    public var favoritesOnly: Bool

    public init(including: String = "", excluding: String = "", genres: String = "", minPlayers: Int = 0,
                fromYear: Int = 0, toYear: Int = 0, favoritesOnly: Bool = false) {
        self.including = including
        self.excluding = excluding
        self.genres = genres
        self.minPlayers = minPlayers
        self.fromYear = fromYear
        self.toYear = toYear
        self.favoritesOnly = favoritesOnly
    }

    /// What a game is checked against.
    public struct Game: Sendable {
        public var title: String
        public var genre: String?
        public var players: String?
        public var year: Int?
        public var favorite: Bool

        public init(title: String, genre: String? = nil, players: String? = nil, year: Int? = nil, favorite: Bool = false) {
            self.title = title
            self.genre = genre
            self.players = players
            self.year = year
            self.favorite = favorite
        }
    }

    public var includedTerms: [String] { Self.terms(including) }
    public var excludedTerms: [String] { Self.terms(excluding) }
    public var genreTerms: [String] { Self.terms(genres) }

    /// Whether anything besides the title narrows the search.
    public var hasCriteria: Bool {
        !genreTerms.isEmpty || minPlayers > 1 || fromYear > 0 || toYear > 0 || favoritesOnly
    }

    /// A search that finds nothing: no title words and nothing else.
    public var isEmpty: Bool { includedTerms.isEmpty && !hasCriteria }

    public func matches(_ title: String) -> Bool {
        matches(Game(title: title))
    }

    public func matches(_ game: Game) -> Bool {
        guard !isEmpty else { return false }
        let included = includedTerms
        if !included.isEmpty, !included.contains(where: { game.title.localizedStandardContains($0) }) { return false }
        if excludedTerms.contains(where: { game.title.localizedStandardContains($0) }) { return false }
        let genres = genreTerms
        if !genres.isEmpty, !genres.contains(where: { game.genre?.localizedStandardContains($0) == true }) { return false }
        if minPlayers > 1, (game.players.map(Self.mostPlayers) ?? 0) < minPlayers { return false }
        if fromYear > 0, (game.year ?? 0) < fromYear { return false }
        if toYear > 0, (game.year ?? .max) > toYear { return false }
        if favoritesOnly, !game.favorite { return false }
        return true
    }

    /// The most players a gamelist's players text allows: "1-4" → 4,
    /// "2" → 2, "1 to 8" → 8.
    static func mostPlayers(_ text: String) -> Int {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.max() ?? 0
    }

    static func terms(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
