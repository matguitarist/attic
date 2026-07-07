import Testing
@testable import RomsBoxModels

@Suite struct ROMFilenameTitleCleanerTests {
    @Test func stripsExtensionAndRegionTag() {
        #expect(ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "Super Metroid (USA).sfc") == "Super Metroid")
    }

    @Test func stripsMultipleTags() {
        #expect(ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "Chrono Trigger (Japan) (En,Fr,De).sfc") == "Chrono Trigger")
    }

    @Test func stripsBracketedRevisionTag() {
        #expect(ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "10-Yard Fight [!].nes") == "10-Yard Fight")
    }

    @Test func leavesPlainTitleUnchanged() {
        #expect(ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "Plain Title.gba") == "Plain Title")
    }

    @Test func stripsMultiRegionTagWithCommas() {
        #expect(ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "Chrono Trigger (USA, Europe).sfc") == "Chrono Trigger")
    }
}
