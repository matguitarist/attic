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
}
