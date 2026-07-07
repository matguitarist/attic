import Testing
@testable import RomsBoxScraping
import RomsBoxModels

@Suite struct ScreenScraperSystemIDTests {
    @Test func mapsAllMVPSystemsToConfirmedIDs() {
        #expect(ScreenScraperSystemID.systemeID(for: .nes) == 3)
        #expect(ScreenScraperSystemID.systemeID(for: .snes) == 4)
        #expect(ScreenScraperSystemID.systemeID(for: .genesis) == 1)
        #expect(ScreenScraperSystemID.systemeID(for: .psx) == 57)
        #expect(ScreenScraperSystemID.systemeID(for: .gba) == 12)
    }

    @Test func unknownSystemReturnsNil() {
        #expect(ScreenScraperSystemID.systemeID(for: CanonicalSystemID("madeup")) == nil)
    }
}
