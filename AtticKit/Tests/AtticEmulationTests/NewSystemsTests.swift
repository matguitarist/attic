import Foundation
import Testing
@testable import AtticEmulation
import AtticModels

@Suite("Arcade boards and add-ons")
struct NewSystemsTests {
    private let systems: [CanonicalSystemID] = [.naomi2, .naomigd, .model2, .stv, .gaelco, .n64dd, .satellaview, .sufami]

    @Test func eachIsAFullSystem() throws {
        for system in systems {
            let definition = try #require(SystemTaxonomy.definition(for: system))
            #expect(SystemTaxonomy.system(forShortName: definition.esdeShortName)?.canonicalID == system)
            #expect(SystemTaxonomy.system(forBatoceraShortName: definition.batoceraShortName)?.canonicalID == system)
            let extensions = SystemROMExtensions.extensions(for: system)?.count ?? 0
            #expect(extensions > 0, "\(system.rawValue)")
            let cores = EmulatorCatalog.recommendation(for: system)?.cores.count ?? 0
            #expect(cores > 0, "\(system.rawValue)")
        }
    }

    @Test func naomi2AndGDROMArentNaomi() {
        #expect(SystemTaxonomy.system(forShortName: "naomi2")?.canonicalID == .naomi2)
        #expect(SystemTaxonomy.system(forShortName: "naomigd")?.canonicalID == .naomigd)
        #expect(SystemTaxonomy.system(forShortName: "naomi")?.canonicalID == .naomi)
    }

    @Test func addOnFilesGoToTheirSystem() {
        #expect(ROMImport.systems(forExtension: "bs").first == .satellaview)
        #expect(ROMImport.systems(forExtension: "st").first == .sufami)
        #expect(ROMImport.systems(forExtension: "ndd").first == .n64dd)
        #expect(ROMImport.systems(forExtension: "sfc").first == .snes)
    }

    @Test func theirBIOSFilesAreKnownDumps() {
        for name in ["BS-X.bin", "STBIOS.bin", "Mupen64plus/IPL.n64", "64DD_IPL.bin"] {
            #expect(!BIOSChecksums.expected(for: name).isEmpty, "\(name)")
        }
    }
}
