import Testing
@testable import AtticModels

struct DumpTagsTests {
    @Test func readsNoIntroAndGoodToolsTags() {
        #expect(DumpTags.kinds(of: "Star Fox 2 (Japan) (Proto).sfc") == [.prototype])
        #expect(DumpTags.kinds(of: "Earthbound (USA) (Beta 2) (2023-01-01).sfc") == [.prototype])
        #expect(DumpTags.kinds(of: "Sonic (World) (Demo, Kiosk).md") == [.demo])
        #expect(DumpTags.kinds(of: "Action 52 (USA) (Unl).nes") == [.unlicensed])
        #expect(DumpTags.kinds(of: "Mario (Europe) (Proto) (Unl).nes") == [.prototype, .unlicensed])
        #expect(DumpTags.kinds(of: "Super Mario Bros. [h1C].nes") == [.hack])
        #expect(DumpTags.kinds(of: "Contra (U) [b2].nes") == [.badDump])
    }

    @Test func releasedGamesHaveNone() {
        #expect(DumpTags.kinds(of: "Super Mario World (USA).sfc").isEmpty)
        #expect(DumpTags.kinds(of: "Zelda (USA) (Rev 1) [!].sfc").isEmpty)
        #expect(DumpTags.kinds(of: "Betrayal at Krondor (USA).zip").isEmpty)
        #expect(DumpTags.kinds(of: "Demolition Man (USA) (En,Fr,De).sfc").isEmpty)
        #expect(DumpTags.kinds(of: "Bomberman (U) [T+Fre].nes").isEmpty)
    }
}
