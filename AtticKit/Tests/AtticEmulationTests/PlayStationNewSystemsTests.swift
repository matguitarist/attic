import Foundation
import Testing
@testable import AtticEmulation
@testable import AtticModels

struct TitleIDTests {
    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "TitleID-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func comesFromTheFileFirst() throws {
        let url = try file("Persona 4 Golden [PCSE00000].psvita", "PCSE00120\n")
        #expect(ArgumentTemplate.substitute("--frontend sdl -F -r {titleID}", romURL: url) == ["--frontend", "sdl", "-F", "-r", "PCSE00120"])
    }

    @Test func elseFromTheName() throws {
        let url = try file("Gravity Rush [PCSA00011].psvita", "")
        #expect(ArgumentTemplate.titleID(romURL: url) == "PCSA00011")
    }

    @Test func ps4GamesRunTheirEboot() {
        let url = URL(fileURLWithPath: "/ROMs/ps4/Bloodborne.ps4")
        #expect(ArgumentTemplate.substitute(EmulatorCatalog.shadPS4.argumentTemplate, romURL: url)
                == ["--fullscreen", "true", "-g", "/ROMs/ps4/Bloodborne.ps4/eboot.bin"])
    }
}

struct Vita3KLibraryTests {
    /// A PARAM.SFO with TITLE and TITLE_ID, laid out like Sony's.
    static func paramSFO(title: String, titleID: String) -> Data {
        let entries = [("TITLE", title), ("TITLE_ID", titleID)]
        var keys = Data(), values = Data(), index = Data()
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        for (key, value) in entries {
            let text = Data(value.utf8) + Data([0])
            index += le(UInt16(keys.count)) + le(UInt16(0x0204)) + le(UInt32(text.count)) + le(UInt32(text.count)) + le(UInt32(values.count))
            keys += Data(key.utf8) + Data([0])
            values += text
        }
        let keyTable = 20 + index.count
        let dataTable = keyTable + keys.count
        return Data([0, 0x50, 0x53, 0x46]) + le(UInt32(0x0101)) + le(UInt32(keyTable)) + le(UInt32(dataTable))
            + le(UInt32(entries.count)) + index + keys + values
    }

    @Test func readsParamSFO() {
        let values = Vita3KLibrary.paramSFO(Self.paramSFO(title: "Gravity Rush", titleID: "PCSA00011"))
        #expect(values == ["TITLE": "Gravity Rush", "TITLE_ID": "PCSA00011"])
    }

    @Test func addsAShortcutPerInstalledGame() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "Vita3K-\(UUID().uuidString)")
        let apps = base.appending(path: "ux0/app")
        let roms = base.appending(path: "ROMs")
        for (id, title) in [("PCSA00011", "Gravity Rush"), ("PCSE00120", "Persona 4: Golden")] {
            let sce = apps.appending(path: "\(id)/sce_sys")
            try FileManager.default.createDirectory(at: sce, withIntermediateDirectories: true)
            try Self.paramSFO(title: title, titleID: id).write(to: sce.appending(path: "param.sfo"))
        }
        // No psvita folder: nothing is written.
        try FileManager.default.createDirectory(at: roms, withIntermediateDirectories: true)
        #expect(Vita3KLibrary.addShortcuts(romsRoots: [roms], appsFolder: apps) == 0)

        let vita = roms.appending(path: "psvita")
        try FileManager.default.createDirectory(at: vita, withIntermediateDirectories: true)
        try Data("PCSA00011".utf8).write(to: vita.appending(path: "My Gravity Rush.psvita"))
        #expect(Vita3KLibrary.addShortcuts(romsRoots: [roms], appsFolder: apps) == 1)
        let added = vita.appending(path: "Persona 4 - Golden [PCSE00120].psvita")
        #expect(try String(contentsOf: added, encoding: .utf8) == "PCSE00120")
        #expect(Vita3KLibrary.addShortcuts(romsRoots: [roms], appsFolder: apps) == 0)
    }
}

struct VersionedAssetTests {
    @Test func starMatchesAVersion() {
        #expect(EmulatorInstaller.matches("shadps4-macos-sdl-0.19.0.zip", suffix: "macos-sdl-*.zip"))
        #expect(!EmulatorInstaller.matches("shadps4-linux-sdl-0.19.0.zip", suffix: "macos-sdl-*.zip"))
        #expect(EmulatorInstaller.matches("macos-arm64-latest.dmg", suffix: "macos-arm64-latest.dmg"))
        #expect(!EmulatorInstaller.matches("macos-latest.dmg", suffix: "macos-arm64-latest.dmg"))
    }

    @Test func newSystemsAreKnown() {
        #expect(SystemTaxonomy.system(forShortName: "psvita")?.canonicalID == .psvita)
        #expect(SystemTaxonomy.system(forShortName: "ps4")?.canonicalID == .ps4)
        #expect(SystemROMExtensions.accepts("Bloodborne.ps4", for: .ps4))
        #expect(EmulatorCatalog.recommendation(for: .psvita)?.standalone == [EmulatorCatalog.vita3K])
    }
}

struct NewSystemsCatalogTests {
    @Test func hacksUseTheBaseSystemsEmulators() {
        #expect(EmulatorCatalog.recommendation(for: .snesh)?.systemID == .snes)
        #expect(EmulatorCatalog.recommendation(for: .psxh)?.standalone == [EmulatorCatalog.duckStation])
    }

    @Test func newCoresMapToTheirSystems() {
        #expect(LibretroDatabase.system(forDatabaseName: "Sharp - X68000") == .x68000)
        #expect(LibretroDatabase.system(forDatabaseName: "TIC-80") == .tic80)
        #expect(SystemTaxonomy.system(forRetroArchSystemID: "mac68k")?.canonicalID == .macintosh)
        #expect(EmulatorCatalog.recommendation(for: .pc88)?.bios.filter(\.required).map(\.fileName) == ["quasi88/n88.rom", "quasi88/n88_0.rom"])
        #expect(EmulatorCatalog.coreSystemFiles["scummvm_libretro"] == "ScummVM.zip")
    }
}

struct FolderNameTests {
    @Test func esdeFoldersTakeAtticsNames() throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "Layout-\(UUID().uuidString)")
        for name in ["downloaded_media/snes/covers", "gamelists/snes", "collections/Mario"] {
            try FileManager.default.createDirectory(at: parent.appending(path: name), withIntermediateDirectories: true)
        }
        let renamed = EmulationFolder.adoptFolderNames(in: parent)
        #expect(renamed.count == 3)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: parent.path))
        #expect(names == ["Media", "Gamelists", "Collections"])
        #expect(FileManager.default.fileExists(atPath: parent.appending(path: "Media/snes/covers").path))
        // Already done: nothing more to do.
        #expect(EmulationFolder.adoptFolderNames(in: parent).isEmpty)
    }
}

struct ConsoleFilesTests {
    private func package(magic: [UInt8], contentID: String) throws -> URL {
        var header = Data(magic) + Data(repeating: 0, count: 0x2C)
        header += Data(contentID.utf8).prefix(0x24)
        header += Data(repeating: 0, count: 0x60 - header.count)
        let url = FileManager.default.temporaryDirectory.appending(path: "pkg-\(UUID().uuidString).pkg")
        try header.write(to: url)
        return url
    }

    @Test func tellsVitaPackagesFromOthers() throws {
        #expect(Vita3KLibrary.isVitaPackage(try package(magic: [0x7F, 0x50, 0x4B, 0x47], contentID: "UP0001-PCSE00120_00-PERSONA4GOLDEN01")))
        #expect(!Vita3KLibrary.isVitaPackage(try package(magic: [0x7F, 0x50, 0x4B, 0x47], contentID: "UP0001-NPUB30910_00-GAME000000000001")))
        #expect(!Vita3KLibrary.isVitaPackage(try package(magic: [0x7F, 0x43, 0x4E, 0x54], contentID: "UP9000-CUSA00900_00-BLOODBORNE000000")))
    }

    @Test func readsDumpedGameFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CUSA00900-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "sce_sys"), withIntermediateDirectories: true)
        try Vita3KLibraryTests.paramSFO(title: "Bloodborne", titleID: "CUSA00900").write(to: folder.appending(path: "sce_sys/param.sfo"))
        let found = try #require(Vita3KLibrary.consoleGame(in: folder))
        #expect(found.system == .ps4 && found.title == "Bloodborne" && found.titleID == "CUSA00900")
    }
}

struct AchievementsLaunchTests {
    private let account = AchievementsAccount(username: "mario", token: "abc123", hardcore: true)

    @Test func retroArchGetsTheAccountOnlyWhenSignedIn() {
        let text = EmulationFolder.retroArchAchievementSettings(account)
        #expect(text.contains("cheevos_enable = \"true\"\n"))
        #expect(text.contains("cheevos_username = \"mario\"\n"))
        #expect(text.contains("cheevos_token = \"abc123\"\n"))
        #expect(text.contains("cheevos_hardcore_mode_enable = \"true\"\n"))
        #expect(EmulationFolder.retroArchAchievementSettings(nil).isEmpty)
    }

    @Test func standaloneEmulatorsGetItInTheirOwnSection() throws {
        let folder = EmulationFolder(root: FileManager.default.temporaryDirectory.appending(path: "Cheevos-\(UUID().uuidString)"))
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, achievements: account)
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.pcsx2, for: .ps2, achievements: account)
        let duck = IniFile(contents: try String(contentsOf: folder.configHome(for: EmulatorCatalog.duckStation).appending(path: EmulatorCatalog.duckStation.portableHome!.settingsRelativePath), encoding: .utf8))
        let pcsx2 = IniFile(contents: try String(contentsOf: folder.configHome(for: EmulatorCatalog.pcsx2).appending(path: EmulatorCatalog.pcsx2.portableHome!.settingsRelativePath), encoding: .utf8))
        #expect(duck.value(section: "Cheevos", key: "Token") == "abc123")
        #expect(duck.value(section: "Cheevos", key: "ChallengeMode") == "true")
        #expect(pcsx2.value(section: "Achievements", key: "Username") == "mario")
        #expect(pcsx2.value(section: "Achievements", key: "Enabled") == "true")
    }
}

struct CatalogCoreNameTests {
    /// The buildbot names each core "<name>_libretro.dylib.zip": a
    /// doubled suffix is a download that doesn't exist.
    @Test func everyCoreIsNamedOnce() {
        for recommendation in EmulatorCatalog.recommendations {
            for core in recommendation.cores {
                #expect(core.coreIdentifier.hasSuffix("_libretro"), "\(core.coreIdentifier)")
                #expect(!core.coreIdentifier.hasSuffix("_libretro_libretro"), "\(core.coreIdentifier)")
            }
        }
    }
}
