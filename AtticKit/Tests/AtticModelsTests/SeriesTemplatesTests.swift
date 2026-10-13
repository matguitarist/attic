import Foundation
import Testing
@testable import AtticModels

struct SeriesTemplatesTests {
    private func template(_ name: String) throws -> SeriesTemplate {
        try #require(SeriesTemplate.all.first { $0.name == name })
    }

    @Test func superMarioLeavesOutSpinOffs() throws {
        let mario = try template("Super Mario")
        #expect(mario.search.matches("Super Mario World (USA)"))
        #expect(mario.search.matches("Super Mario Bros. 3 (USA)"))
        #expect(mario.search.matches("Super Mario Land 2 - 6 Golden Coins (USA, Europe)"))
        #expect(!mario.search.matches("Super Mario Kart (USA)"))
        #expect(!mario.search.matches("Mario Tennis (USA)"))
        #expect(!mario.search.matches("Dr. Mario (World)"))
    }

    @Test func sonicSkipsLookalikes() throws {
        let sonic = try template("Sonic the Hedgehog")
        #expect(sonic.search.matches("Sonic the Hedgehog 2 (World)"))
        #expect(!sonic.search.matches("Sonic Wings 3"))
        #expect(!sonic.search.matches("Sonic Blast Man (USA)"))
    }

    @Test func namesAreUniqueAndSearchesSet() {
        #expect(Set(SeriesTemplate.all.map(\.name)).count == SeriesTemplate.all.count)
        #expect(SeriesTemplate.all.allSatisfy { !$0.search.isEmpty })
    }

    @Test func collectionFilesRoundTrip() throws {
        let file = CollectionFile(id: UUID(), name: "Mario", including: "Super Mario", system: "snes", addsMatchingGames: true,
                                  games: [.init(system: "snes", path: "smw.sfc", title: "Super Mario World")], excluded: ["snes/kart.sfc"])
        #expect(try CollectionFile.decoded(from: file.encoded()) == file)
        #expect(CollectionFile.folderName(for: "Mario: The / Best?") == "Mario- The - Best-")
    }

    @Test func logoNamesFollowThemeNaming() {
        #expect(SeriesTemplate.logoNames(for: "Super Mario") == ["mario", "supermario"])
        #expect(SeriesTemplate.logoNames(for: "Pokémon") == ["pokemon"])
        #expect(SeriesTemplate.logoNames(for: "The Legend of Zelda") == ["zelda", "thelegendofzelda", "legendofzelda"])
        #expect(SeriesTemplate.logoNames(for: "F-Zero") == ["fzero"])
        #expect(SeriesTemplate.logoNames(for: "My RPGs") == ["myrpgs"])
    }
}
