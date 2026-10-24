import Testing
@testable import AtticModels

struct PhysicalMediumTests {
    @Test func knowsWhatGamesCameOn() {
        #expect(PhysicalMedium.of(.nes) == .cartridge)
        #expect(PhysicalMedium.of(.dreamcast) == .disc)
        #expect(PhysicalMedium.of(.naomigd) == .disc)
        #expect(PhysicalMedium.of(.naomi) == .board)
        #expect(PhysicalMedium.of(.pcengine) == .card)
        #expect(PhysicalMedium.of(.fds) == .disk)
        #expect(PhysicalMedium.of(.cps2) == .board)
        #expect(PhysicalMedium.of(.amiga) == .disk)
        #expect(PhysicalMedium.of(.zxspectrum) == .cassette)
        #expect(PhysicalMedium.of(.steam) == nil)
        // A hack folder's games are its system's.
        #expect(PhysicalMedium.of(CanonicalSystemID(rawValue: "psxh")) == .disc)
    }
}
