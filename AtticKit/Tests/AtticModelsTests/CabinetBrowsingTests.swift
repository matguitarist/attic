import Testing
@testable import AtticModels

struct CabinetBrowsingTests {
    @Test func searchNeedsEveryWord() {
        #expect(TitleBrowsing.matches("Super Mario World", query: "mario world"))
        #expect(TitleBrowsing.matches("Pokémon Red", query: "pokemon"))
        #expect(!TitleBrowsing.matches("Super Mario World", query: "mario kart"))
        #expect(!TitleBrowsing.matches("Anything", query: "  "))
    }

    @Test func titlesFileUnderTheirFirstLetter() {
        #expect(TitleBrowsing.letter(of: "Zelda") == "Z")
        #expect(TitleBrowsing.letter(of: "éclair") == "E")
        #expect(TitleBrowsing.letter(of: "'96 Flag Rally") == "#")
        #expect(TitleBrowsing.letter(of: "1942") == "#")
        #expect(TitleBrowsing.letter(of: "") == "#")
    }

    @Test func jumpsGoLetterByLetter() {
        let titles = ["1942", "Alpha", "Apple", "Axe", "Bravo", "Delta", "Dune"]
        #expect(TitleBrowsing.jump(from: 0, in: titles, forward: true) == 1)
        #expect(TitleBrowsing.jump(from: 2, in: titles, forward: true) == 4)
        #expect(TitleBrowsing.jump(from: 5, in: titles, forward: true) == nil)
        // Back: this letter's first, then the previous letter's.
        #expect(TitleBrowsing.jump(from: 3, in: titles, forward: false) == 1)
        #expect(TitleBrowsing.jump(from: 1, in: titles, forward: false) == 0)
        #expect(TitleBrowsing.jump(from: 5, in: titles, forward: false) == 4)
        #expect(TitleBrowsing.jump(from: 6, in: titles, forward: false) == 5)
        #expect(TitleBrowsing.jump(from: 0, in: titles, forward: false) == nil)
        #expect(TitleBrowsing.jump(from: 0, in: [], forward: true) == nil)
    }
}
