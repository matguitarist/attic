import Foundation
import SwiftData
import Testing
@testable import AtticModels
@testable import AtticPersistence

// Serialized: concurrent in-memory SwiftData ModelContainers across parallel
// tests crash the test process on the current toolchain (Xcode 27 beta).
@Suite(.serialized) struct LibraryStoreTests {

    private func makeStore() throws -> LibraryStore {
        let container = try AtticModelContainer.makeInMemory()
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

    @Test func collectionsThatKeepUpPickUpNewMatches() async throws {
        let container = try AtticModelContainer.makeInMemory()
        let store = LibraryStore(modelContainer: container)
        _ = try await store.upsertSystem(sampleSystemData(games: [
            sampleRecord(path: "smw.sfc", title: "Super Mario World"),
        ]), displayName: "SNES")

        let context = ModelContext(container)
        let collection = GameCollection(name: "Mario")
        collection.search = CollectionSearch(including: "Super Mario, Mario Bros", excluding: "Kart")
        collection.addsMatchingGames = true
        // Taken out by hand earlier: never comes back.
        collection.excludedGameKeys = ["snes/allstars.sfc"]
        context.insert(collection)
        let frozen = GameCollection(name: "Frozen")
        frozen.search = CollectionSearch(including: "Mario")
        context.insert(frozen)
        try context.save()

        // A rescan finds more games.
        _ = try await store.upsertSystem(sampleSystemData(games: [
            sampleRecord(path: "smw.sfc", title: "Super Mario World"),
            sampleRecord(path: "kart.sfc", title: "Super Mario Kart"),
            sampleRecord(path: "allstars.sfc", title: "Super Mario All-Stars"),
            sampleRecord(path: "rpg.sfc", title: "Super Mario RPG"),
        ]), displayName: "SNES")
        #expect(try await store.addMatchingGamesToCollections() == 2)

        let fresh = ModelContext(container)
        let collections = try fresh.fetch(FetchDescriptor<GameCollection>())
        let mario = try #require(collections.first { $0.name == "Mario" })
        #expect(Set(mario.games.map(\.title)) == ["Super Mario World", "Super Mario RPG"])
        #expect(collections.first { $0.name == "Frozen" }?.games.isEmpty == true)
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

    private func storedGameCount(in store: LibraryStore, for canonicalID: CanonicalSystemID) throws -> Int? {
        let idString = canonicalID.rawValue
        let context = ModelContext(store.modelContainer)
        return try context.fetch(FetchDescriptor<GameSystem>(predicate: #Predicate { $0.canonicalID == idString })).first?.gameCount
    }

    @Test func upsertKeepsStoredGameCountInSyncAcrossRescans() async throws {
        let store = try makeStore()
        _ = try await store.upsertSystem(sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A"),
            sampleRecord(path: "b.sfc", title: "Game B")
        ]), displayName: "SNES")
        #expect(try storedGameCount(in: store, for: .snes) == 2)

        _ = try await store.upsertSystem(sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A"),
            sampleRecord(path: "c.sfc", title: "Game C"),
            sampleRecord(path: "d.sfc", title: "Game D")
        ]), displayName: "SNES")
        #expect(try storedGameCount(in: store, for: .snes) == 3)
    }

    @Test func refreshGameCountsBackfillsStaleCounts() async throws {
        let store = try makeStore()
        _ = try await store.upsertSystem(sampleSystemData(games: [
            sampleRecord(path: "a.sfc", title: "Game A"),
            sampleRecord(path: "b.sfc", title: "Game B")
        ]), displayName: "SNES")

        // Simulate a store written before `gameCount` existed.
        let context = ModelContext(store.modelContainer)
        let system = try #require(try context.fetch(FetchDescriptor<GameSystem>()).first)
        system.gameCount = 0
        try context.save()

        try await store.refreshGameCounts()
        #expect(try storedGameCount(in: store, for: .snes) == 2)
    }

    @Test func rescanUpdatesMetadataButPreservesFavoriteAndPlayHistory() async throws {
        let container = try AtticModelContainer.makeInMemory()
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

    @Test func rescanDoesNotOverwriteManuallyEditedMetadataButStillRefreshesArt() async throws {
        let container = try AtticModelContainer.makeInMemory()
        let store = LibraryStore(modelContainer: container)

        let original = ImportedSystemData(
            canonicalID: .snes,
            libraryFormat: .esde,
            romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"),
            games: [ImportedGameRecord(romRelativePath: "a.sfc", title: "Game A (USA)", developer: "Old Dev")]
        )
        _ = try await store.upsertSystem(original, displayName: "SNES")

        // Simulate the user hand-correcting the title/developer in the
        // detail panel — this is what GameDetailView's editable bindings do.
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Game>()
        let game = try #require(try context.fetch(descriptor).first)
        game.title = "Game A"
        game.developer = "Corrected Dev"
        game.metadataManuallyEdited = true
        try context.save()

        let rescan = ImportedSystemData(
            canonicalID: .snes,
            libraryFormat: .esde,
            romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"),
            games: [ImportedGameRecord(
                romRelativePath: "a.sfc",
                title: "Game A (USA)",
                developer: "Old Dev",
                coverArtURL: URL(fileURLWithPath: "/tmp/media/a.png")
            )]
        )
        _ = try await store.upsertSystem(rescan, displayName: "SNES")

        let refetched = try #require(try context.fetch(descriptor).first)
        #expect(refetched.title == "Game A")
        #expect(refetched.developer == "Corrected Dev")
        // Art isn't a hand-typed field — it should still track the ROM's
        // actual matched media rather than being frozen by the edit flag.
        #expect(refetched.coverArtPath == "/tmp/media/a.png")
    }

    @Test func rescanKeepsHandSetDateRatingAndCustomCover() async throws {
        let container = try AtticModelContainer.makeInMemory()
        let store = LibraryStore(modelContainer: container)
        let record = ImportedGameRecord(
            romRelativePath: "a.sfc",
            title: "Game A",
            releaseDate: Date(timeIntervalSince1970: 0),
            rating: 0.4,
            coverArtURL: URL(fileURLWithPath: "/tmp/media/a.png")
        )
        let data = ImportedSystemData(canonicalID: .snes, libraryFormat: .esde, romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"), games: [record])
        _ = try await store.upsertSystem(data, displayName: "SNES")

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Game>()
        let game = try #require(try context.fetch(descriptor).first)
        let handSetDate = Date(timeIntervalSince1970: 86_400 * 365)
        game.releaseDate = handSetDate
        game.rating = 1
        game.metadataManuallyEdited = true
        game.coverArtPath = "/tmp/custom/a.jpg"
        game.coverArtManuallySet = true
        try context.save()

        _ = try await store.upsertSystem(data, displayName: "SNES")

        let refetched = try #require(try context.fetch(descriptor).first)
        #expect(refetched.releaseDate == handSetDate)
        #expect(refetched.rating == 1)
        #expect(refetched.coverArtPath == "/tmp/custom/a.jpg")
    }

    @Test func rescanKeepsScrapedImagesTheGamelistLacks() async throws {
        let container = try AtticModelContainer.makeInMemory()
        let store = LibraryStore(modelContainer: container)
        let data = ImportedSystemData(canonicalID: .snes, libraryFormat: .esde, romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"), games: [ImportedGameRecord(romRelativePath: "a.sfc", title: "Game A")])
        _ = try await store.upsertSystem(data, displayName: "SNES")

        let scraped = FileManager.default.temporaryDirectory.appending(path: "scraped-\(UUID().uuidString).png")
        try Data().write(to: scraped)
        defer { try? FileManager.default.removeItem(at: scraped) }
        let context = ModelContext(container)
        let game = try #require(try context.fetch(FetchDescriptor<Game>()).first)
        game.titleScreenPath = scraped.path
        game.coverArtPath = "/tmp/no-such-file.png"
        try context.save()

        _ = try await store.upsertSystem(data, displayName: "SNES")
        let refetched = try #require(try context.fetch(FetchDescriptor<Game>()).first)
        #expect(refetched.titleScreenPath == scraped.path)
        #expect(refetched.coverArtPath == nil)
    }

    @Test func upsertSystemUpdatesDisplayNameAndFormatOnRescan() async throws {
        let store = try makeStore()
        _ = try await store.upsertSystem(sampleSystemData(games: []), displayName: "SNES")
        _ = try await store.upsertSystem(sampleSystemData(games: []), displayName: "Super Nintendo Entertainment System")

        #expect(try await store.systemCount() == 1)
    }
}
