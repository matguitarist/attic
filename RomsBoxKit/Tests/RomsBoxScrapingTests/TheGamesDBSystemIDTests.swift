import Testing
@testable import RomsBoxScraping
import RomsBoxModels

@Suite struct TheGamesDBSystemIDTests {
    @Test func mapsAllMVPSystemsToConfirmedIDs() {
        #expect(TheGamesDBSystemID.platformID(for: .nes) == 7)
        #expect(TheGamesDBSystemID.platformID(for: .snes) == 6)
        #expect(TheGamesDBSystemID.platformID(for: .genesis) == 18)
        #expect(TheGamesDBSystemID.platformID(for: .psx) == 10)
        #expect(TheGamesDBSystemID.platformID(for: .gba) == 5)
    }

    @Test func unknownSystemReturnsNil() {
        #expect(TheGamesDBSystemID.platformID(for: CanonicalSystemID("madeup")) == nil)
    }
}
