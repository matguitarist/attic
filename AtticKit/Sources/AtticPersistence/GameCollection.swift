import Foundation
import SwiftData
import AtticModels

/// A user-made group of games ("Zelda", "Castlevania", "Couch co-op"…),
/// across any systems. A game can be in any number of collections; deleting
/// a collection never deletes its games.
@Model
public final class GameCollection {
    /// Stable identity for sidebar selection — `PersistentIdentifier` is
    /// awkward to carry around in plain value types like LibrarySelection.
    @Attribute(.unique) public var collectionID: UUID
    public var name: String
    public var createdDate: Date

    @Relationship(deleteRule: .nullify, inverse: \Game.collections)
    public var games: [Game] = []

    /// The search that found its games, kept so it can be run again or
    /// changed later (see `CollectionSearch`).
    public var searchIncluding: String = ""
    public var searchExcluding: String = ""
    /// Only games of this system, when set.
    public var searchSystemID: String?
    /// The rest of the search (see `CollectionSearch`).
    public var searchGenres: String = ""
    public var searchMinPlayers: Int = 0
    public var searchFromYear: Int = 0
    public var searchToYear: Int = 0
    public var searchFavoritesOnly: Bool = false
    /// New games the search finds are added after each library scan.
    public var addsMatchingGames: Bool = false
    /// Games taken out of the collection or unticked from its search, as
    /// `Game.collectionKey`, so the search never adds them back.
    public var excludedGameKeys: [String] = []

    public init(name: String, games: [Game] = []) {
        self.collectionID = UUID()
        self.name = name
        self.createdDate = .now
        self.games = games
    }

    public var search: CollectionSearch {
        get {
            CollectionSearch(including: searchIncluding, excluding: searchExcluding, genres: searchGenres,
                             minPlayers: searchMinPlayers, fromYear: searchFromYear, toYear: searchToYear,
                             favoritesOnly: searchFavoritesOnly)
        }
        set {
            searchIncluding = newValue.including
            searchExcluding = newValue.excluding
            searchGenres = newValue.genres
            searchMinPlayers = newValue.minPlayers
            searchFromYear = newValue.fromYear
            searchToYear = newValue.toYear
            searchFavoritesOnly = newValue.favoritesOnly
        }
    }

    /// Whether the collection's search would add `game`.
    public func searchMatches(_ game: Game) -> Bool {
        (searchSystemID == nil || game.systemCanonicalID == searchSystemID)
            && search.matches(game.searchable)
            && !excludedGameKeys.contains(game.collectionKey)
    }

    public func contains(_ game: Game) -> Bool {
        game.collections.contains { $0.collectionID == collectionID }
    }

    /// Adds or removes `game`, keeping both sides of the relationship in step.
    public func setContains(_ game: Game, _ isMember: Bool) {
        if isMember, !contains(game) {
            games.append(game)
        } else if !isMember {
            games.removeAll { $0.persistentModelID == game.persistentModelID }
        }
    }
}

extension Game {
    /// What a collection's search looks at.
    public var searchable: CollectionSearch.Game {
        let year = releaseDate.map { date -> Int in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar.component(.year, from: date)
        }
        return CollectionSearch.Game(title: title, genre: genre, players: players, year: year, favorite: favorite)
    }
}
