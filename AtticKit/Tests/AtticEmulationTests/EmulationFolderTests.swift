import Foundation
import Testing
@testable import AtticEmulation
@testable import AtticModels

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

    @Test func coreOptionsReplaceExistingKeysAndAppendNewOnes() throws {
        try FileManager.default.createDirectory(at: folder.retroArchConfigDirectory, withIntermediateDirectories: true)
        try "fbneo-neogeo-mode = \"DIPSWITCH\"\nfbneo-dipswitch-mslug-Free_play = \"Off\"\n"
            .write(to: folder.retroArchCoreOptionsFile, atomically: true, encoding: .utf8)

        try folder.setRetroArchCoreOptions(["fbneo-dipswitch-mslug-Free_play": "On", "fbneo-dipswitch-kof98-Free_play": "On"])

        let contents = try String(contentsOf: folder.retroArchCoreOptionsFile, encoding: .utf8)
        #expect(contents == """
        fbneo-neogeo-mode = "DIPSWITCH"
        fbneo-dipswitch-mslug-Free_play = "On"
        fbneo-dipswitch-kof98-Free_play = "On"

        """)
    }

    @Test func coreOptionsCreateTheFileWhenMissing() throws {
        try folder.setRetroArchCoreOptions(["a": "1"])
        #expect(try String(contentsOf: folder.retroArchCoreOptionsFile, encoding: .utf8) == "a = \"1\"\n")
    }

    @Test func neoGeoFreePlayTargetsTheRomsetWithFinalBurnNeoOnly() {
        let rom = URL(fileURLWithPath: "/ROMs/neogeo/mslug.zip")
        func options(_ system: CanonicalSystemID, _ core: String, freePlay: Bool = true) -> [String: String] {
            CoreLaunchOptions.options(system: system, coreIdentifier: core, romURL: rom, neoGeoFreePlay: freePlay)
        }
        #expect(options(.neogeo, "fbneo_libretro") == ["fbneo-dipswitch-mslug-Free_play": "On"])
        #expect(options(.neogeo, "fbneo_libretro", freePlay: false) == ["fbneo-dipswitch-mslug-Free_play": "Off"])
        #expect(options(.neogeo, "geolith_libretro").isEmpty)
        #expect(options(.snes, "fbneo_libretro").isEmpty)
    }

    @Test func virtualBoyAlwaysTurnsOffTheOpenGLOnlyVRMode() {
        let options = CoreLaunchOptions.options(
            system: .virtualboy, coreIdentifier: "mednafen_vb_libretro", romURL: URL(fileURLWithPath: "/g.vb"), neoGeoFreePlay: true
        )
        #expect(options == ["vb_vr": "disabled"])
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
        #expect(try String(contentsOf: append, encoding: .utf8) == folder.retroArchPathsConfig(for: .gba) + EmulationFolder.retroArchLogSettings)
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

    @Test func retroArchQuitComboIsStartSelectWithoutConfirmation() {
        let on = folder.retroArchPathsConfig(for: .snes, controller: .init(quitWithSelectStart: true))
        #expect(on.contains("input_quit_gamepad_combo = \"4\""))
        #expect(on.contains("quit_press_twice = \"false\""))
        let off = folder.retroArchPathsConfig(for: .snes, controller: .init(quitWithSelectStart: false))
        #expect(!off.contains("input_quit_gamepad_combo"))
        // RetroArch saved Attic's combo into its config: turning it off resets it.
        let undo = folder.retroArchPathsConfig(
            for: .snes, controller: .init(quitWithSelectStart: false),
            savedConfig: ["input_quit_gamepad_combo": "4"], previouslyWritten: ["input_quit_gamepad_combo": "4"]
        )
        #expect(undo.contains("input_quit_gamepad_combo = \"0\""))
    }

    @Test func layoutPicksRetroArchMenuConfirmButton() {
        #expect(folder.retroArchPathsConfig(for: .snes, controller: .init(layout: .classic)).contains("menu_swap_ok_cancel_buttons = \"true\""))
        #expect(folder.retroArchPathsConfig(for: .snes, controller: .init(layout: .nintendo)).contains("menu_swap_ok_cancel_buttons = \"false\""))
    }

    @Test func defaultMappingWritesNoBinds() {
        #expect(!folder.retroArchPathsConfig(for: .snes).contains("_btn"))
    }

    @Test func customMappingBindsEveryButtonOfEveryPort() {
        var mapping = ButtonMapping.faceButtonsSwapped
        mapping.set(.r1, for: .l2)
        let config = folder.retroArchPathsConfig(for: .snes, controller: .init(buttonMapping: mapping))
        for port in 1...4 {
            #expect(config.contains("input_player\(port)_a_btn = \"0\""))
            #expect(config.contains("input_player\(port)_b_btn = \"8\""))
            #expect(config.contains("input_player\(port)_x_btn = \"1\""))
            #expect(config.contains("input_player\(port)_y_btn = \"9\""))
            #expect(config.contains("input_player\(port)_start_btn = \"3\""))
            #expect(config.contains("input_player\(port)_l2_btn = \"11\""))
            // Moved off its trigger, so the trigger's axis no longer presses it.
            #expect(config.contains("input_player\(port)_l2_axis = \"+9\""))
            #expect(!config.contains("input_player\(port)_r2_axis"))
        }
    }

    @Test func backToDefaultMappingClearsOnlyAtticBinds() {
        let previous = ["input_player1_a_btn": "0", "input_player1_b_btn": "8"]
        let saved = ["input_player1_a_btn": "0", "input_player1_b_btn": "3"]
        let config = folder.retroArchPathsConfig(for: .snes, savedConfig: saved, previouslyWritten: previous)
        #expect(config.contains("input_player1_a_btn = \"nul\""))
        #expect(!config.contains("input_player1_b_btn"), "a bind the user changed in RetroArch stays")
    }

    @Test func mappingSkipsNonMFiDrivers() {
        let config = folder.retroArchPathsConfig(
            for: .snes, controller: .init(buttonMapping: .faceButtonsSwapped), savedConfig: ["input_joypad_driver": "hid"]
        )
        #expect(!config.contains("_btn"))
    }

    @Test func prepareRetroArchLaunchRemembersWhatItWrote() throws {
        _ = try folder.prepareRetroArchLaunch(for: .snes, controller: .init(buttonMapping: .faceButtonsSwapped))
        #expect(folder.readOwnedSettings("retroarch")?["input_player1_a_btn"] == "0")
        _ = try folder.prepareRetroArchLaunch(for: .snes, controller: .init())
        #expect(folder.readOwnedSettings("retroarch")?["input_player1_a_btn"] == nil)
    }

    @Test func leftStickAsDPadUsesAnalogDPadMode() {
        let config = folder.retroArchPathsConfig(for: .snes, controller: .init(leftStickAsDPad: true))
        #expect(config.contains("input_player1_analog_dpad_mode = \"1\""))
        #expect(config.contains("input_player4_analog_dpad_mode = \"1\""))
    }

    @Test func duckStationFollowsTheMappingAndRestoresDefaults() throws {
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, buttonMapping: .faceButtonsSwapped)
        var ini = IniFile(contents: try String(contentsOf: duckStationSettingsFile, encoding: .utf8))
        #expect(ini.value(section: "Pad1", key: "Cross") == "SDL-0/B")
        #expect(ini.value(section: "Pad1", key: "Circle") == "SDL-0/A")
        #expect(ini.value(section: "Pad1", key: "Start") == "SDL-0/Start")

        // The user rebinds Square in DuckStation; Attic's mapping goes back to default.
        ini.set(section: "Pad1", key: "Square", value: "SDL-0/RightShoulder")
        try ini.contents.write(to: duckStationSettingsFile, atomically: true, encoding: .utf8)
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, buttonMapping: .default)
        ini = IniFile(contents: try String(contentsOf: duckStationSettingsFile, encoding: .utf8))
        #expect(ini.value(section: "Pad1", key: "Cross") == "SDL-0/A")
        #expect(ini.value(section: "Pad1", key: "Circle") == "SDL-0/B")
        #expect(ini.value(section: "Pad1", key: "Square") == "SDL-0/RightShoulder")
    }

    @Test func retroArchConfigParserUnquotesValues() {
        let parsed = EmulationFolder.parseRetroArchConfig("a = \"1\"\nb=\"two words\"\n# comment\n")
        #expect(parsed == ["a": "1", "b": "two words"])
    }

    private var duckStationSettingsFile: URL {
        folder.root.appending(path: "Config/DuckStation/Library/Application Support/DuckStation/settings.ini")
    }

    @Test func duckStationGetsControllerMappingAndQuitHotkey() throws {
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx)
        let ini = IniFile(contents: try String(contentsOf: duckStationSettingsFile, encoding: .utf8))
        #expect(ini.value(section: "Pad1", key: "Cross") == "SDL-0/A")
        #expect(ini.value(section: "Pad1", key: "Select") == "SDL-0/Back")
        #expect(ini.value(section: "InputSources", key: "SDL") == "true")
        #expect(ini.value(section: "Hotkeys", key: "PowerOff") == "SDL-0/Back & SDL-0/Start")
    }

    @Test func duckStationControllerDefaultsNeverOverwriteUserMapping() throws {
        try FileManager.default.createDirectory(at: duckStationSettingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[Pad1]\nCross = SDL-0/B\n".write(to: duckStationSettingsFile, atomically: true, encoding: .utf8)
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx)
        let ini = IniFile(contents: try String(contentsOf: duckStationSettingsFile, encoding: .utf8))
        #expect(ini.value(section: "Pad1", key: "Cross") == "SDL-0/B")
        #expect(ini.value(section: "Pad1", key: "Circle") == "SDL-0/B", "missing keys still get filled in")
    }

    @Test func disablingQuitComboRemovesOnlyAtticsBinding() throws {
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, quitCombo: true)
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, quitCombo: false)
        var ini = IniFile(contents: try String(contentsOf: duckStationSettingsFile, encoding: .utf8))
        #expect(ini.value(section: "Hotkeys", key: "PowerOff") == nil)

        // A binding the user chose themselves survives turning it off.
        ini.set(section: "Hotkeys", key: "PowerOff", value: "Keyboard/F12")
        try ini.contents.write(to: duckStationSettingsFile, atomically: true, encoding: .utf8)
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, quitCombo: false)
        let after = IniFile(contents: try String(contentsOf: duckStationSettingsFile, encoding: .utf8))
        #expect(after.value(section: "Hotkeys", key: "PowerOff") == "Keyboard/F12")
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
