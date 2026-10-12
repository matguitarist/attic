import Testing
@testable import AtticScraping
import AtticModels

@Suite struct TheGamesDBSystemIDTests {
    @Test func mapsAllMVPSystemsToConfirmedIDs() {
        #expect(TheGamesDBSystemID.platformID(for: .nes) == 7)
        #expect(TheGamesDBSystemID.platformID(for: .snes) == 6)
        #expect(TheGamesDBSystemID.platformID(for: .genesis) == 18)
        #expect(TheGamesDBSystemID.platformID(for: .psx) == 10)
        #expect(TheGamesDBSystemID.platformID(for: .gba) == 5)
    }

    @Test func mapsExpandedSystemsToConfirmedIDs() {
        #expect(TheGamesDBSystemID.platformID(for: .mastersystem) == 35)
        #expect(TheGamesDBSystemID.platformID(for: .gamegear) == 20)
        #expect(TheGamesDBSystemID.platformID(for: .segacd) == 21)
        #expect(TheGamesDBSystemID.platformID(for: .saturn) == 17)
        #expect(TheGamesDBSystemID.platformID(for: .dreamcast) == 16)
        #expect(TheGamesDBSystemID.platformID(for: .sega32x) == 33)
        #expect(TheGamesDBSystemID.platformID(for: .atari2600) == 22)
        #expect(TheGamesDBSystemID.platformID(for: .atari5200) == 26)
        #expect(TheGamesDBSystemID.platformID(for: .atari7800) == 27)
        #expect(TheGamesDBSystemID.platformID(for: .atarilynx) == 4924)
        #expect(TheGamesDBSystemID.platformID(for: .atarijaguar) == 28)
        #expect(TheGamesDBSystemID.platformID(for: .pcengine) == 34)
        #expect(TheGamesDBSystemID.platformID(for: .pcenginecd) == 4955)
        #expect(TheGamesDBSystemID.platformID(for: .pcfx) == 4930)
        #expect(TheGamesDBSystemID.platformID(for: .threedo) == 25)
        #expect(TheGamesDBSystemID.platformID(for: .cdi) == 4917)
    }

    /// TheGamesDB genuinely has no distinct SuperGrafx platform (confirmed
    /// against its full platform list) — this documents that as an
    /// intentional gap rather than a missed mapping, so ScrapeCoordinator
    /// correctly reports "not supported" instead of guessing an ID.
    @Test func superGrafxIsIntentionallyUnmapped() {
        #expect(TheGamesDBSystemID.platformID(for: .supergrafx) == nil)
    }

    @Test func unknownSystemReturnsNil() {
        #expect(TheGamesDBSystemID.platformID(for: CanonicalSystemID("madeup")) == nil)
    }
}
