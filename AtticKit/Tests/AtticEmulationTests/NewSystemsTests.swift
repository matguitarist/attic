import Foundation
import Testing
@testable import AtticEmulation
import AtticModels

@Suite("Arcade boards and add-ons")
struct NewSystemsTests {
    private let systems: [CanonicalSystemID] = [.naomi2, .naomigd, .model1, .model2, .stv, .gaelco, .n64dd, .satellaview, .sufami]

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

    @Test func keishoIsTheDefaultForModel1And2() throws {
        for system in [CanonicalSystemID.model1, .model2] {
            let recommendation = try #require(EmulatorCatalog.recommendation(for: system))
            #expect(recommendation.prefersStandalone)
            #expect(recommendation.standalone.first == EmulatorCatalog.keisho)
            #expect(EmulatorCatalog.keisho.systems.contains(system))
        }
        #expect(EmulatorCatalog.standaloneEmulators.contains(EmulatorCatalog.keisho))
    }

    @Test func keishoKeepsItsDataInTheEmulationFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = EmulationFolder(root: root)
        let arguments = try folder.keishoArguments(for: .model2)
        #expect(arguments == ["--config", folder.configHome(for: EmulatorCatalog.keisho).path, "--nvram", folder.saves(for: .model2).path])
        #expect(FileManager.default.fileExists(atPath: folder.saves(for: .model2).path))
    }

    @Test func keishoInstallsFromItsRenamedProject() throws {
        let keisho = EmulatorCatalog.keisho
        #expect(keisho.appBundleName == "Keisho.app")
        #expect(keisho.executableRelativePath == "Contents/MacOS/Keisho")
        #expect(keisho.downloadURL.absoluteString.contains("Keisho-Emu/Keisho"))
        #expect(keisho.systems.contains(.model3))
        #expect(EmulatorCatalog.recommendation(for: .model3)?.prefersStandalone == false)
        #expect(EmulatorCatalog.renamedEmulators["sm2-emu"]?.emulator == keisho)
    }

    @Test func anSm2EmuSetupBecomesKeisho() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = EmulationFolder(root: root)
        let fileManager = FileManager.default
        let oldConfig = folder.config.appending(path: "sm2-emu")
        try fileManager.createDirectory(at: oldConfig, withIntermediateDirectories: true)
        try Data("[video]".utf8).write(to: oldConfig.appending(path: "sm2-emu.ini"))
        let oldApp = folder.emulators.appending(path: "sm2-emu/sm2-emu.app/Contents/MacOS")
        try fileManager.createDirectory(at: oldApp, withIntermediateDirectories: true)

        folder.adoptRenamedEmulators()
        let settings = folder.configHome(for: EmulatorCatalog.keisho).appending(path: "keisho.ini")
        #expect(try String(contentsOf: settings, encoding: .utf8) == "[video]")
        #expect(!fileManager.fileExists(atPath: oldConfig.path))
        // Kept until Keisho is installed, so the games still have something.
        #expect(fileManager.fileExists(atPath: oldApp.path))

        let newApp = folder.emulators.appending(path: "Keisho/Keisho.app/Contents/MacOS")
        try fileManager.createDirectory(at: newApp, withIntermediateDirectories: true)
        try Data().write(to: newApp.appending(path: "Keisho"))
        folder.adoptRenamedEmulators()
        #expect(!fileManager.fileExists(atPath: folder.emulators.appending(path: "sm2-emu").path))
    }

    @Test func keishoFindsTheIOBoardBesideTheGame() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = EmulationFolder(root: root)
        let set = folder.bios.appending(path: "mame/bios/model1io.zip")
        try FileManager.default.createDirectory(at: set.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("io".utf8).write(to: set)
        let games = root.appending(path: "ROMs/model2")
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)

        _ = try folder.keishoArguments(for: .model2, romURL: games.appending(path: "daytona.zip"))
        #expect(FileManager.default.fileExists(atPath: games.appending(path: "model1io.zip").path))
        #expect(!FileManager.default.fileExists(atPath: games.appending(path: "model1io2.zip").path))
        #expect(ArcadeBIOSSets.isBIOSSet("model1io.zip", system: .model2))
        #expect(EmulatorCatalog.recommendation(for: .model1)?.bios == EmulatorCatalog.model1IOBoards)
    }

    @Test func odinFindsHikarusSharedSetsBesideTheGame() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = EmulationFolder(root: root)
        for name in ["hikaru", "mie"] {
            let set = folder.bios.appending(path: "mame/bios/\(name).zip")
            try FileManager.default.createDirectory(at: set.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: set)
        }
        let games = root.appending(path: "ROMs/hikaru")
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)

        _ = try folder.odinLaunchArguments(for: .hikaru, romURL: games.appending(path: "braveff.zip"))
        #expect(FileManager.default.fileExists(atPath: games.appending(path: "hikaru.zip").path))
        #expect(FileManager.default.fileExists(atPath: games.appending(path: "mie.zip").path))
        #expect(EmulatorCatalog.recommendation(for: .hikaru)?.bios == EmulatorCatalog.hikaruSharedSets)
    }

    @Test func odinIsTheDefaultForHikaruAndGaelco() throws {
        for system in [CanonicalSystemID.hikaru, .gaelco] {
            let recommendation = try #require(EmulatorCatalog.recommendation(for: system))
            #expect(recommendation.prefersStandalone)
            #expect(recommendation.standalone.first == EmulatorCatalog.odin)
        }
        let hikaru = try #require(SystemTaxonomy.definition(for: .hikaru))
        #expect(SystemTaxonomy.system(forBatoceraShortName: hikaru.batoceraShortName)?.canonicalID == .hikaru)
        #expect(ArcadeBIOSSets.isBIOSSet("mie.zip", system: .hikaru))
        #expect(ArcadeBIOSSets.isBIOSSet("hikaru.zip", system: .hikaru))
        #expect(!ArcadeBIOSSets.isBIOSSet("braveff.zip", system: .hikaru))
    }

    @Test func odinKeepsItsSavesInTheEmulationFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = EmulationFolder(root: root)
        let settings = folder.configHome(for: EmulatorCatalog.odin).appending(path: "odin.ini")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[display]\nscale = 2\n# saves = old\n".write(to: settings, atomically: true, encoding: .utf8)

        #expect(try folder.odinLaunchArguments(for: .hikaru) == ["-c", settings.path])
        let ini = IniFile(contents: try String(contentsOf: settings, encoding: .utf8))
        #expect(ini.value(section: "paths", key: "saves") == folder.saves(for: .hikaru).path)
        #expect(ini.value(section: "paths", key: "states") == folder.states(for: .hikaru).path)
        #expect(ini.value(section: "display", key: "scale") == "2")
    }

    @Test func systemsFromTheLogoPackAreFullSystems() throws {
        let systems: [CanonicalSystemID] = [.amigacd32, .cdtv, .gx4000, .megaduck, .moto, .spectravideo, .supervision, .x1, .segapico, .pet]
        for system in systems {
            let definition = try #require(SystemTaxonomy.definition(for: system))
            #expect(SystemTaxonomy.system(forShortName: definition.esdeShortName)?.canonicalID == system)
            #expect(SystemTaxonomy.system(forBatoceraShortName: definition.batoceraShortName)?.canonicalID == system)
            #expect(SystemROMExtensions.extensions(for: system)?.isEmpty == false, "\(system.rawValue)")
            #expect(EmulatorCatalog.recommendation(for: system)?.recommendedCore != nil, "\(system.rawValue)")
        }
        #expect(SystemTaxonomy.system(forShortName: "to8")?.canonicalID == .moto)
        #expect(SystemTaxonomy.system(forShortName: "pico")?.canonicalID == .segapico)
        for name in ["kick40060.CD32", "kick40060.CD32.ext", "kick34005.CDTV", "xmil/IPLROM.X1"] {
            #expect(!BIOSChecksums.expected(for: name).isEmpty, "\(name)")
        }
    }

    @Test func amigaDiscsBootTheirOwnMachine() {
        let disc = URL(fileURLWithPath: "/ROMs/game.chd")
        #expect(CoreLaunchOptions.options(system: .cdtv, coreIdentifier: "puae_libretro", romURL: disc) == ["puae_model_cd": "CDTV"])
        #expect(CoreLaunchOptions.options(system: .amigacd32, coreIdentifier: "puae_libretro", romURL: disc) == ["puae_model_cd": "CD32"])
        #expect(CoreLaunchOptions.options(system: .amiga, coreIdentifier: "puae_libretro", romURL: disc).isEmpty)
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
