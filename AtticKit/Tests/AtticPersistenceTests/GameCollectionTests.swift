import Foundation
import Testing
import SwiftData
@testable import AtticPersistence
import AtticModels

@MainActor
struct GameCollectionTests {
    private func makeGames(_ titles: [String], in context: ModelContext) -> [Game] {
        titles.map { title in
            let game = Game(system: nil, systemCanonicalID: .snes, romRelativePath: "\(title).sfc", romAbsoluteURL: URL(fileURLWithPath: "/tmp/\(title).sfc"), title: title)
            context.insert(game)
            return game
        }
    }

    @Test func membershipIsTrackedOnBothSides() throws {
        let container = try AtticModelContainer.makeInMemory()
        let context = container.mainContext
        let games = makeGames(["Super Metroid", "Zelda"], in: context)
        let collection = GameCollection(name: "Metroid")
        context.insert(collection)

        collection.setContains(games[0], true)
        collection.setContains(games[0], true)
        try context.save()
        #expect(collection.games.count == 1)
        #expect(games[0].collections.map(\.name) == ["Metroid"])
        #expect(collection.contains(games[0]))
        #expect(!collection.contains(games[1]))

        collection.setContains(games[0], false)
        try context.save()
        #expect(collection.games.isEmpty)
        #expect(games[0].collections.isEmpty)
    }

    @Test func predicateFindsAGamesCollection() throws {
        let container = try AtticModelContainer.makeInMemory()
        let context = container.mainContext
        let games = makeGames(["Super Metroid", "Metroid Fusion", "Zelda"], in: context)
        let collection = GameCollection(name: "Metroid", games: Array(games.prefix(2)))
        context.insert(collection)
        try context.save()

        let id = collection.collectionID
        let found = try context.fetch(FetchDescriptor<Game>(predicate: #Predicate { game in
            game.collections.contains { $0.collectionID == id }
        }, sortBy: [SortDescriptor(\.title)]))
        #expect(found.map(\.title) == ["Metroid Fusion", "Super Metroid"])
    }

    @Test func deletingACollectionKeepsItsGames() throws {
        let container = try AtticModelContainer.makeInMemory()
        let context = container.mainContext
        let games = makeGames(["Castlevania"], in: context)
        let collection = GameCollection(name: "Castlevania", games: games)
        context.insert(collection)
        try context.save()

        context.delete(collection)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Game>()) == 1)
        #expect(games[0].collections.isEmpty)
    }
}
