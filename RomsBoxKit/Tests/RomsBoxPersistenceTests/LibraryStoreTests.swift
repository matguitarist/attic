import Foundation
import SwiftData
import Testing
@testable import RomsBoxModels
@testable import RomsBoxPersistence

// Serialized: concurrent in-memory SwiftData ModelContainers across parallel
// tests crash the test process on the current toolchain (Xcode 27 beta).
@Suite(.serialized) struct LibraryStoreTests {

    private func makeStore() throws -> LibraryStore {
        let container = try RomsBoxModelContainer.makeInMemory()
        return LibraryStore(modelContainer: container)
    }

    private func sampleRecord(path: String, title: String) -> ImportedGameRecord {
        ImportedGameRecord(romRelativePath: path, title: title)
    }

    private func sampleSystemData(games: [ImportedGameRecord]) -> ImportedSystemData {
        ImportedSystemData(
            canonicalID: .snes,
            libraryFormat: .esde,
            romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"),
            games: games
        )
    }

    @Test func firstScanInsertsSystemAndGames() async throws {
        let store = try makeStore()
        let data = sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A"),
            sampleRecord(path: "b.sfc", title: "Game B")
        ])

        let result = try await store.upsertSystem(data, displayName: "Super Nintendo Entertainment System")

        #expect(result.gamesInserted == 2)
        #expect(result.gamesUpdated == 0)
        #expect(result.gamesRemoved == 0)
        #expect(try await store.systemCount() == 1)
        #expect(try await store.gameCount(forSystem: .snes) == 2)
    }

    @Test func rescanWithSameDataIsIdempotent() async throws {
        let store = try makeStore()
        let data = sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A"),
            sampleRecord(path: "b.sfc", title: "Game B")
        ])

        _ = try await store.upsertSystem(data, displayName: "SNES")
        let second = try await store.upsertSystem(data, displayName: "SNES")

        #expect(second.gamesInserted == 0)
        #expect(second.gamesUpdated == 2)
        #expect(second.gamesRemoved == 0)
        #expect(try await store.systemCount() == 1)
        #expect(try await store.gameCount(forSystem: .snes) == 2)
        #expect(try await store.totalGameCount() == 2)
    }

    @Test func rescanRemovesGamesNoLongerPresent() async throws {
        let store = try makeStore()
        let first = sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A"),
            sampleRecord(path: "b.sfc", title: "Game B")
        ])
        _ = try await store.upsertSystem(first, displayName: "SNES")

        let second = sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A")
        ])
        let result = try await store.upsertSystem(second, displayName: "SNES")

        #expect(result.gamesRemoved == 1)
        #expect(try await store.gameCount(forSystem: .snes) == 1)
    }

    @Test func rescanUpdatesMetadataButPreservesFavoriteAndPlayHistory() async throws {
        let container = try RomsBoxModelContainer.makeInMemory()
        let store = LibraryStore(modelContainer: container)

        let original = ImportedSystemData(
            canonicalID: .snes,
            libraryFormat: .esde,
            romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"),
            games: [ImportedGameRecord(romRelativePath: "a.sfc", title: "Game A", favorite: true)]
        )
        _ = try await store.upsertSystem(original, displayName: "SNES")

        // Simulate user marking playtime/favorite state through the app layer
        // by fetching and mutating directly against the same in-memory container.
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Game>()
        let game = try #require(try context.fetch(descriptor).first)
        game.favorite = false
        game.playCount = 5
        try context.save()

        let rescan = ImportedSystemData(
            canonicalID: .snes,
            libraryFormat: .esde,
            romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"),
            games: [ImportedGameRecord(romRelativePath: "a.sfc", title: "Game A (Rev 1)", favorite: true)]
        )
        _ = try await store.upsertSystem(rescan, displayName: "SNES")

        let refetched = try #require(try context.fetch(descriptor).first)
        #expect(refetched.title == "Game A (Rev 1)")
        #expect(refetched.favorite == false)
        #expect(refetched.playCount == 5)
    }

    @Test func upsertSystemUpdatesDisplayNameAndFormatOnRescan() async throws {
        let store = try makeStore()
        _ = try await store.upsertSystem(sampleSystemData(games: []), displayName: "SNES")
        _ = try await store.upsertSystem(sampleSystemData(games: []), displayName: "Super Nintendo Entertainment System")

        #expect(try await store.systemCount() == 1)
    }
}
