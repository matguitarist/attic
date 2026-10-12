import Foundation
import SwiftData

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

    public init(name: String, games: [Game] = []) {
        self.collectionID = UUID()
        self.name = name
        self.createdDate = .now
        self.games = games
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
