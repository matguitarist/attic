import Testing
@testable import RomsBoxModels

@Suite struct SystemTaxonomyTests {

    @Test func batoceraMegadriveMapsToCanonicalGenesis() {
        #expect(SystemTaxonomy.system(forBatoceraShortName: "megadrive")?.canonicalID == .genesis)
    }

    @Test func esdeGenesisMapsToCanonicalGenesis() {
        #expect(SystemTaxonomy.system(forESDEShortName: "genesis")?.canonicalID == .genesis)
    }

    @Test func esdeDoesNotRecognizeBatoceraMegadriveName() {
        #expect(SystemTaxonomy.system(forESDEShortName: "megadrive") == nil)
    }

    @Test func batoceraDoesNotRecognizeESDEGenesisName() {
        #expect(SystemTaxonomy.system(forBatoceraShortName: "genesis") == nil)
    }

    @Test func retroArchSuperNesMapsToCanonicalSnes() {
        #expect(SystemTaxonomy.system(forRetroArchSystemID: "super_nes")?.canonicalID == .snes)
    }

    @Test func retroArchSnesAliasAlsoMapsToCanonicalSnes() {
        #expect(SystemTaxonomy.system(forRetroArchSystemID: "snes")?.canonicalID == .snes)
    }

    @Test(arguments: [
        ("nes", CanonicalSystemID.nes),
        ("snes", CanonicalSystemID.snes),
        ("psx", CanonicalSystemID.psx),
        ("gba", CanonicalSystemID.gba)
    ])
    func agreeingShortNamesMapIdenticallyInBothConventions(shortName: String, expected: CanonicalSystemID) {
        #expect(SystemTaxonomy.system(forBatoceraShortName: shortName)?.canonicalID == expected)
        #expect(SystemTaxonomy.system(forESDEShortName: shortName)?.canonicalID == expected)
    }

    @Test func unknownShortNameReturnsNil() {
        #expect(SystemTaxonomy.system(forShortName: "totally-unknown-system") == nil)
    }

    @Test func shortNameLookupFallsBackAcrossConventions() {
        #expect(SystemTaxonomy.system(forShortName: "megadrive")?.canonicalID == .genesis)
        #expect(SystemTaxonomy.system(forShortName: "genesis")?.canonicalID == .genesis)
    }

    @Test func definitionRoundTripsFromCanonicalID() {
        let definition = SystemTaxonomy.definition(for: .genesis)
        #expect(definition?.batoceraShortName == "megadrive")
        #expect(definition?.esdeShortName == "genesis")
    }

    @Test func everyMVPSystemHasAUniqueCanonicalID() {
        let ids = SystemTaxonomy.mvpSystems.map(\.canonicalID)
        #expect(ids.count == Set(ids).count)
    }
}
