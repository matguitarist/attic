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

    // Confirmed against real installed cores' .info files (genesis_plus_gx,
    // mednafen_psx/swanstation, mgba) rather than guessed.
    @Test func retroArchMegaDriveMapsToCanonicalGenesis() {
        #expect(SystemTaxonomy.system(forRetroArchSystemID: "mega_drive")?.canonicalID == .genesis)
    }

    @Test func retroArchPlaystationMapsToCanonicalPsx() {
        #expect(SystemTaxonomy.system(forRetroArchSystemID: "playstation")?.canonicalID == .psx)
    }

    @Test func retroArchGameBoyAdvanceMapsToCanonicalGba() {
        #expect(SystemTaxonomy.system(forRetroArchSystemID: "game_boy_advance")?.canonicalID == .gba)
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

    @Test func everySystemHasAUniqueCanonicalID() {
        let ids = SystemTaxonomy.allSystems.map(\.canonicalID)
        #expect(ids.count == Set(ids).count)
    }

    @Test func everySystemHasUniqueBatoceraAndESDEShortNames() {
        let batoceraNames = SystemTaxonomy.allSystems.map(\.batoceraShortName)
        #expect(batoceraNames.count == Set(batoceraNames).count)

        let esdeNames = SystemTaxonomy.allSystems.map(\.esdeShortName)
        #expect(esdeNames.count == Set(esdeNames).count)
    }

    @Test func everySystemsRetroArchIDsAreGloballyUnique() {
        let allIDs = SystemTaxonomy.allSystems.flatMap(\.retroArchSystemIDs)
        #expect(allIDs.count == Set(allIDs).count)
    }

    @Test func newFoldersAreRecognizedWithTheirCategory() {
        #expect(SystemTaxonomy.system(forShortName: "triforce")?.category == .arcade)
        #expect(SystemTaxonomy.system(forShortName: "neogeo")?.category == .arcade)
        #expect(SystemTaxonomy.system(forShortName: "virtualboy")?.category == .handheld)
    }

    @Test func handheldsAndConsolesAreCategorized() {
        #expect(SystemTaxonomy.definition(for: .gba)?.category == .handheld)
        #expect(SystemTaxonomy.definition(for: .gamegear)?.category == .handheld)
        #expect(SystemTaxonomy.definition(for: .atarilynx)?.category == .handheld)
        #expect(SystemTaxonomy.definition(for: .snes)?.category == .console)
        #expect(SystemTaxonomy.definition(for: .pcengine)?.category == .console)
    }
}

struct SystemROMExtensionsTests {
    @Test func acceptsTheSystemsFileTypesCaseInsensitively() {
        #expect(SystemROMExtensions.accepts("Super Metroid (USA).SFC", for: .snes))
        #expect(SystemROMExtensions.accepts("sub/Castlevania (USA).chd", for: .psx))
        #expect(SystemROMExtensions.accepts("Demon's Souls.ps3", for: .ps3))
        #expect(SystemROMExtensions.accepts("sf2.zip", for: .cps1))
    }

    @Test func rejectsStrayFiles() {
        #expect(!SystemROMExtensions.accepts("test.8xp", for: .wiiu))
        #expect(!SystemROMExtensions.accepts("readme.txt", for: .snes))
        #expect(!SystemROMExtensions.accepts("Game.srm", for: .snes))
        #expect(!SystemROMExtensions.accepts("noextension", for: .nes))
    }

    @Test func everySystemHasAList() {
        for system in SystemTaxonomy.allSystems {
            #expect(SystemROMExtensions.extensions(for: system.canonicalID)?.isEmpty == false, "\(system.canonicalID.rawValue)")
        }
    }
}
