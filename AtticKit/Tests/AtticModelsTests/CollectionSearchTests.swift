import Foundation
import Testing
@testable import AtticModels

struct CollectionSearchTests {
    @Test func anyIncludedTermButNoExcludedOne() {
        let search = CollectionSearch(including: "Super Mario, Mario Bros", excluding: "Tennis, kart")
        #expect(search.matches("Super Mario World (USA)"))
        #expect(search.matches("Mario Bros. (World)"))
        #expect(search.matches("super mario kart") == false)
        #expect(!search.matches("Mario Tennis (USA)"))
        #expect(!search.matches("Dr. Mario"))
    }

    @Test func caseAccentsAndSpacesDontMatter() {
        let search = CollectionSearch(including: "  pokemon ,, ")
        #expect(search.includedTerms == ["pokemon"])
        #expect(search.matches("Pokémon Red"))
    }

    @Test func nothingToSearchMatchesNothing() {
        #expect(CollectionSearch(including: " , ").isEmpty)
        #expect(!CollectionSearch().matches("Anything"))
    }

    @Test func criteriaBeyondTheTitle() {
        let couch = CollectionSearch(genres: "Beat'em Up, Fighting", minPlayers: 2, fromYear: 1990, toYear: 1999)
        #expect(!couch.isEmpty)
        #expect(couch.matches(.init(title: "Streets of Rage 2", genre: "Beat'em Up", players: "1-2", year: 1992)))
        // One player, the wrong decade, the wrong genre, no year known.
        #expect(!couch.matches(.init(title: "Final Fight", genre: "Beat'em Up", players: "1", year: 1991)))
        #expect(!couch.matches(.init(title: "Double Dragon", genre: "Beat'em Up", players: "1-2", year: 1987)))
        #expect(!couch.matches(.init(title: "Sonic 2", genre: "Platform", players: "1-2", year: 1992)))
        #expect(!couch.matches(.init(title: "Unknown", genre: "Fighting", players: "2")))

        let favorites = CollectionSearch(including: "Mario", favoritesOnly: true)
        #expect(favorites.matches(.init(title: "Super Mario World", favorite: true)))
        #expect(!favorites.matches(.init(title: "Super Mario World", favorite: false)))
        #expect(CollectionSearch.mostPlayers("1 to 8") == 8)
    }

    @Test func collectionFilesKeepTheCriteria() throws {
        var file = CollectionFile(id: UUID(), name: "Couch")
        file.setCriteria(from: CollectionSearch(genres: "Racing", minPlayers: 4))
        let read = try CollectionFile.decoded(from: file.encoded())
        #expect(read.search == CollectionSearch(genres: "Racing", minPlayers: 4))
        // A file from before the criteria reads as before.
        let old = #"{"format":1,"id":"\#(UUID().uuidString)","name":"Old","including":"Zelda","excluding":"","addsMatchingGames":true,"games":[],"excluded":[]}"#
        #expect(try CollectionFile.decoded(from: Data(old.utf8)).search == CollectionSearch(including: "Zelda"))
    }
}
