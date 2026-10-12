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
