import Foundation
import Testing
@testable import RomsBoxEmulation
@testable import RomsBoxModels

struct EmulationFolderTests {
    private let root: URL
    private let folder: EmulationFolder

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "EmulationFolderTests-\(UUID().uuidString)")
        folder = EmulationFolder(root: root.appending(path: "Emulation"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func defaultRootIsTheParentOfAROMsFolder() {
        let roms = URL(fileURLWithPath: "/Volumes/Games/Emulation/ROMs")
        #expect(EmulationFolder.defaultRoot(romsRoots: [roms]).path == "/Volumes/Games/Emulation")
    }

    @Test func defaultRootFallsBackToHomeEmulation() {
        let other = URL(fileURLWithPath: "/Volumes/Games/my-library")
        let expected = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Emulation").path
        #expect(EmulationFolder.defaultRoot(romsRoots: [other]).path == expected)
    }

    @Test func retroArchPathsConfigPointsEverythingIntoTheFolderPerSystem() {
        let config = folder.retroArchPathsConfig(for: .snes)
        #expect(config.contains("system_directory = \"\(folder.bios.path)\""))
        #expect(config.contains("libretro_directory = \"\(folder.cores.path)\""))
        #expect(config.contains("savefile_directory = \"\(folder.root.path)/Saves/snes\""))
        #expect(config.contains("savestate_directory = \"\(folder.root.path)/States/snes\""))
        #expect(config.contains("sort_savefiles_enable = \"false\""))
    }

    @Test func prepareRetroArchLaunchWritesConfigAndCreatesFolders() throws {
        let (config, append) = try folder.prepareRetroArchLaunch(for: .gba)
        #expect(config == folder.retroArchConfigFile)
        #expect(try String(contentsOf: append, encoding: .utf8) == folder.retroArchPathsConfig(for: .gba))
        #expect(FileManager.default.fileExists(atPath: folder.saves(for: .gba).path))
        #expect(FileManager.default.fileExists(atPath: folder.states(for: .gba).path))
    }

    @Test func seedingCopiesExistingConfigOnlyOnce() throws {
        let existing = root.appending(path: "retroarch.cfg")
        try "video_driver = \"metal\"".write(to: existing, atomically: true, encoding: .utf8)
        try folder.seedRetroArchConfig(from: existing)
        #expect(try String(contentsOf: folder.retroArchConfigFile, encoding: .utf8) == "video_driver = \"metal\"")

        try "video_driver = \"gl\"".write(to: existing, atomically: true, encoding: .utf8)
        try folder.seedRetroArchConfig(from: existing)
        #expect(try String(contentsOf: folder.retroArchConfigFile, encoding: .utf8) == "video_driver = \"metal\"")
    }

    @Test func duckStationLaunchRedirectsHomeAndFillsSettings() throws {
        let environment = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx)

        let home = folder.root.appending(path: "Config/DuckStation")
        #expect(environment == ["HOME": home.path])
        let settings = try String(contentsOf: home.appending(path: "Library/Application Support/DuckStation/settings.ini"), encoding: .utf8)
        let ini = IniFile(contents: settings)
        #expect(ini.value(section: "Main", key: "SetupWizardIncomplete") == "false")
        #expect(ini.value(section: "BIOS", key: "SearchDirectory") == folder.bios.path)
        #expect(ini.value(section: "MemoryCards", key: "Directory") == folder.saves(for: .psx).path)
        #expect(ini.value(section: "Folders", key: "SaveStates") == folder.states(for: .psx).path)
    }

    @Test func duckStationLaunchKeepsTheUsersOtherSettings() throws {
        let settingsFile = folder.root.appending(path: "Config/DuckStation/Library/Application Support/DuckStation/settings.ini")
        try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[GPU]\nResolutionScale = 4\n[BIOS]\nSearchDirectory = bios\n".write(to: settingsFile, atomically: true, encoding: .utf8)

        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx)

        let ini = IniFile(contents: try String(contentsOf: settingsFile, encoding: .utf8))
        #expect(ini.value(section: "GPU", key: "ResolutionScale") == "4")
        #expect(ini.value(section: "BIOS", key: "SearchDirectory") == folder.bios.path)
    }

    @Test func emulatorWithoutPortableHomeGetsNoEnvironment() throws {
        let nonPortable = StandaloneEmulator(
            id: "example",
            name: "Example",
            summary: "",
            appBundleName: "Example.app",
            executableRelativePath: "Contents/MacOS/Example",
            argumentTemplate: "{romPath}",
            downloadURL: URL(string: "https://example.com/example.zip")!,
            archive: .zip,
            homepageURL: URL(string: "https://example.com")!,
            license: "MIT",
            systems: [.dreamcast],
            portableHome: nil
        )
        #expect(try folder.prepareStandaloneLaunch(of: nonPortable, for: .dreamcast).isEmpty)
    }

    @Test func copyMissingFilesCopiesOnlyWhatsAbsent() throws {
        let source = root.appending(path: "system")
        let destination = folder.bios
        try FileManager.default.createDirectory(at: source.appending(path: "dc"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "new".write(to: source.appending(path: "scph5501.bin"), atomically: true, encoding: .utf8)
        try "nested".write(to: source.appending(path: "dc/dc_boot.bin"), atomically: true, encoding: .utf8)
        try "source copy".write(to: source.appending(path: "lynxboot.img"), atomically: true, encoding: .utf8)
        try "already here".write(to: destination.appending(path: "lynxboot.img"), atomically: true, encoding: .utf8)

        let copied = try EmulationFolder.copyMissingFiles(from: source, to: destination)

        #expect(copied == ["dc/dc_boot.bin", "scph5501.bin"])
        #expect(try String(contentsOf: destination.appending(path: "lynxboot.img"), encoding: .utf8) == "already here")
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "scph5501.bin").path), "Source must be left in place")
    }
}

struct IniFileTests {
    @Test func replacesExistingKeyInPlace() {
        var ini = IniFile(contents: "; comment\n[BIOS]\nSearchDirectory = bios\nFastBoot = true\n")
        ini.set(section: "BIOS", key: "SearchDirectory", value: "/x")
        #expect(ini.contents == "; comment\n[BIOS]\nSearchDirectory = /x\nFastBoot = true\n")
    }

    @Test func addsKeyToExistingSectionBeforeBlankLines() {
        var ini = IniFile(contents: "[Main]\nA = 1\n\n[GPU]\nB = 2\n")
        ini.set(section: "Main", key: "C", value: "3")
        #expect(ini.contents == "[Main]\nA = 1\nC = 3\n\n[GPU]\nB = 2\n")
    }

    @Test func addsMissingSectionAtEnd() {
        var ini = IniFile(contents: "[Main]\nA = 1\n")
        ini.set(section: "Folders", key: "SaveStates", value: "/s")
        #expect(ini.contents == "[Main]\nA = 1\n[Folders]\nSaveStates = /s\n")
        #expect(ini.value(section: "Folders", key: "SaveStates") == "/s")
    }

    @Test func sameKeyInAnotherSectionIsUntouched() {
        var ini = IniFile(contents: "[MemoryCards]\nDirectory = memcards\n[Other]\nDirectory = keep\n")
        ini.set(section: "MemoryCards", key: "Directory", value: "/m")
        #expect(ini.value(section: "Other", key: "Directory") == "keep")
        #expect(ini.value(section: "MemoryCards", key: "Directory") == "/m")
    }

    @Test func startsFromEmpty() {
        var ini = IniFile(contents: "")
        ini.set(section: "Main", key: "A", value: "1")
        #expect(ini.contents == "[Main]\nA = 1\n")
    }
}
