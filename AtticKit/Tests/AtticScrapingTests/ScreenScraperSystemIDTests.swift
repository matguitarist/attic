import Testing
@testable import AtticScraping
import AtticModels

@Suite struct ScreenScraperSystemIDTests {
    @Test func mapsAllMVPSystemsToConfirmedIDs() {
        #expect(ScreenScraperSystemID.systemeID(for: .nes) == 3)
        #expect(ScreenScraperSystemID.systemeID(for: .snes) == 4)
        #expect(ScreenScraperSystemID.systemeID(for: .genesis) == 1)
        #expect(ScreenScraperSystemID.systemeID(for: .psx) == 57)
        #expect(ScreenScraperSystemID.systemeID(for: .gba) == 12)
    }

    @Test func mapsExpandedSystemsToConfirmedIDs() {
        #expect(ScreenScraperSystemID.systemeID(for: .mastersystem) == 2)
        #expect(ScreenScraperSystemID.systemeID(for: .gamegear) == 21)
        #expect(ScreenScraperSystemID.systemeID(for: .segacd) == 20)
        #expect(ScreenScraperSystemID.systemeID(for: .saturn) == 22)
        #expect(ScreenScraperSystemID.systemeID(for: .dreamcast) == 23)
        #expect(ScreenScraperSystemID.systemeID(for: .sega32x) == 19)
        #expect(ScreenScraperSystemID.systemeID(for: .atari2600) == 26)
        #expect(ScreenScraperSystemID.systemeID(for: .atari5200) == 40)
        #expect(ScreenScraperSystemID.systemeID(for: .atari7800) == 41)
        #expect(ScreenScraperSystemID.systemeID(for: .atarilynx) == 28)
        #expect(ScreenScraperSystemID.systemeID(for: .atarijaguar) == 27)
        #expect(ScreenScraperSystemID.systemeID(for: .pcengine) == 31)
        #expect(ScreenScraperSystemID.systemeID(for: .pcenginecd) == 114)
        #expect(ScreenScraperSystemID.systemeID(for: .pcfx) == 72)
        #expect(ScreenScraperSystemID.systemeID(for: .supergrafx) == 105)
        #expect(ScreenScraperSystemID.systemeID(for: .threedo) == 29)
        #expect(ScreenScraperSystemID.systemeID(for: .cdi) == 133)
    }

    @Test func unknownSystemReturnsNil() {
        #expect(ScreenScraperSystemID.systemeID(for: CanonicalSystemID("madeup")) == nil)
    }

    @Test func allTaxonomySystemsHaveAScreenScraperMapping() {
        // No published ScreenScraper system ID found for Triforce yet.
        // Steam games get their info and art from the Steam store.
        let knownGaps: Set<CanonicalSystemID> = [.triforce, .steam]
        for definition in SystemTaxonomy.allSystems where !knownGaps.contains(definition.canonicalID) {
            #expect(ScreenScraperSystemID.systemeID(for: definition.canonicalID) != nil, "missing ScreenScraper ID for \(definition.canonicalID)")
        }
    }
}
