import Foundation
import Testing
@testable import AtticEmulation
@testable import AtticModels

struct SystemSettingsSupportTests {
    @Test func offersWhatTheEmulatorCanDo() {
        let snes = SystemSettingsSupport.settings(for: .snes, backend: .retroArch(coreIdentifier: "snes9x_libretro"))
        #expect(snes == [.look, .integerScaling, .runAhead, .rewind, .resume])

        let psxCore = SystemSettingsSupport.settings(for: .psx, backend: .retroArch(coreIdentifier: "swanstation_libretro"))
        #expect(psxCore == [.look, .integerScaling, .internalResolution, .widescreen, .geometryCorrection, .resume])

        #expect(SystemSettingsSupport.settings(for: .psx, backend: .duckStation) == [.internalResolution, .widescreen, .geometryCorrection, .rewind])
        #expect(SystemSettingsSupport.settings(for: .gamecube, backend: .dolphin) == [.internalResolution, .widescreen])
        #expect(SystemSettingsSupport.settings(for: .psx, backend: .other).isEmpty)
    }

    @Test func handheldsGetTheLCDLook() {
        #expect(SystemSettingsSupport.looks(for: .gba).contains(.lcd))
        #expect(!SystemSettingsSupport.looks(for: .snes).contains(.lcd))
    }

    @Test func defaultSettingsChangeNothing() {
        let settings = SystemSettings()
        #expect(SystemSettingsSupport.retroArchConfig(settings, system: .snes).isEmpty)
        #expect(SystemSettingsSupport.coreOptions(settings, core: "swanstation_libretro").isEmpty)
        #expect(SystemSettingsSupport.dolphinArguments(settings).isEmpty)
        #expect(SystemSettingsSupport.duckStationSettings(settings).allSatisfy { $0.value == nil })
    }

    @Test func retroArchConfigCoversPictureAndGameplay() {
        var settings = SystemSettings()
        settings.look = .crt
        settings.integerScaling = true
        settings.runAheadFrames = 1
        settings.rewind = true
        settings.resume = true
        let config = Dictionary(uniqueKeysWithValues: SystemSettingsSupport.retroArchConfig(settings, system: .snes).map { ($0.key, $0.value) })
        #expect(config == [
            "video_shader_enable": "true",
            "video_scale_integer": "true",
            "run_ahead_enabled": "true",
            "run_ahead_frames": "1",
            "run_ahead_secondary_instance": "true",
            "rewind_enable": "true",
            "savestate_auto_save": "true",
            "savestate_auto_load": "true"
        ])
    }

    @Test func threeDSystemsNeverGetRewindOrRunAhead() {
        var settings = SystemSettings()
        settings.runAheadFrames = 2
        settings.rewind = true
        #expect(SystemSettingsSupport.retroArchConfig(settings, system: .n64).isEmpty)
    }

    @Test func coreOptionsUseEachCoresOwnValues() {
        var settings = SystemSettings()
        settings.internalResolution = 4
        settings.widescreen = true
        settings.geometryCorrection = true
        #expect(SystemSettingsSupport.coreOptions(settings, core: "mednafen_psx_hw_libretro") == [
            "beetle_psx_hw_internal_resolution": "4x",
            "beetle_psx_hw_widescreen_hack": "enabled",
            "beetle_psx_hw_pgxp_mode": "memory only"
        ])
        #expect(SystemSettingsSupport.coreOptions(settings, core: "flycast_libretro") == [
            "reicast_internal_resolution": "2560x1920",
            "reicast_widescreen_hack": "enabled"
        ])
        settings.internalResolution = 1
        #expect(SystemSettingsSupport.coreOptions(settings, core: "pcsx2_libretro")["pcsx2_upscale_multiplier"] == "1x (Native)")
    }

    @Test func everyCoreOptionHasADefault() {
        var settings = SystemSettings()
        settings.internalResolution = 2
        settings.widescreen = true
        settings.geometryCorrection = true
        settings.unlimitedSprites = true
        settings.lcdColors = true
        for core in SystemSettingsSupport.coreOptions.keys {
            for key in SystemSettingsSupport.coreOptions(settings, core: core).keys {
                #expect(SystemSettingsSupport.coreOptionDefault(key) != nil, "\(key) has no default")
            }
        }
    }

    @Test func dolphinOverridesAreForThisRunOnly() {
        var settings = SystemSettings()
        settings.internalResolution = 3
        settings.widescreen = false
        #expect(SystemSettingsSupport.dolphinArguments(settings) == [
            "-C", "GFX.Settings.InternalResolution=3", "-C", "GFX.Settings.wideScreenHack=False"
        ])
    }
}

struct SystemSettingsLaunchTests {
    private let folder: EmulationFolder

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SystemSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        folder = EmulationFolder(root: root.appending(path: "Emulation"))
    }

    private func retroArchConfig() throws -> [String: String] {
        EmulationFolder.parseRetroArchConfig(try String(contentsOf: folder.retroArchConfigFile, encoding: .utf8))
    }

    /// What RetroArch does on exit: saves the appended settings into its
    /// main config.
    private func simulateRetroArchSavingOnExit() throws {
        var config = (try? retroArchConfig()) ?? [:]
        config.merge(EmulationFolder.parseRetroArchConfig(try String(contentsOf: folder.retroArchPathsConfigFile, encoding: .utf8))) { $1 }
        try config.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n").write(to: folder.retroArchConfigFile, atomically: true, encoding: .utf8)
    }

    @Test func aSettingGoesBackToTheUsersOwnValueOnAnotherSystem() throws {
        try folder.createStructure()
        try "video_scale_integer = \"true\"\n".write(to: folder.retroArchConfigFile, atomically: true, encoding: .utf8)

        var gba = SystemSettings()
        gba.integerScaling = false
        _ = try folder.prepareRetroArchLaunch(for: .gba, systemSettings: gba)
        try simulateRetroArchSavingOnExit()
        #expect(try retroArchConfig()["video_scale_integer"] == "false")

        // A system with no setting of its own gets the user's value back.
        _ = try folder.prepareRetroArchLaunch(for: .snes)
        let appended = EmulationFolder.parseRetroArchConfig(try String(contentsOf: folder.retroArchPathsConfigFile, encoding: .utf8))
        #expect(appended["video_scale_integer"] == "true")
    }

    @Test func aValueTheUserChangedInRetroArchIsLeftAlone() {
        let owned = ["rewind_enable": EmulationFolder.OwnedValue(written: "true", original: "false")]
        let result = EmulationFolder.reconcileKeepingOriginals(
            desired: [], owned: owned, current: ["rewind_enable": "false"], fallback: { _ in nil }
        )
        #expect(result.write.isEmpty)
        #expect(result.owned.isEmpty)
    }

    @Test func coreOptionsAreSetAndPutBack() throws {
        try folder.createStructure()
        var psx = SystemSettings()
        psx.internalResolution = 4
        try folder.setSystemCoreOptions(psx, core: "swanstation_libretro")
        var options = EmulationFolder.parseRetroArchConfig(try String(contentsOf: folder.retroArchCoreOptionsFile, encoding: .utf8))
        #expect(options["swanstation_GPU_ResolutionScale"] == "4")

        try folder.setSystemCoreOptions(SystemSettings(), core: "snes9x_libretro")
        options = EmulationFolder.parseRetroArchConfig(try String(contentsOf: folder.retroArchCoreOptionsFile, encoding: .utf8))
        #expect(options["swanstation_GPU_ResolutionScale"] == "1")
    }

    @Test func duckStationGetsSystemSettingsAndLosesThemAgain() throws {
        var psx = SystemSettings()
        psx.internalResolution = 4
        psx.widescreen = true
        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx, systemSettings: psx)
        let file = folder.configHome(for: EmulatorCatalog.duckStation).appending(path: "Library/Application Support/DuckStation/settings.ini")
        var ini = IniFile(contents: try String(contentsOf: file, encoding: .utf8))
        #expect(ini.value(section: "GPU", key: "ResolutionScale") == "4")
        #expect(ini.value(section: "GPU", key: "WidescreenHack") == "true")
        #expect(ini.value(section: "Display", key: "AspectRatio") == "16:9")

        _ = try folder.prepareStandaloneLaunch(of: EmulatorCatalog.duckStation, for: .psx)
        ini = IniFile(contents: try String(contentsOf: file, encoding: .utf8))
        #expect(ini.value(section: "GPU", key: "ResolutionScale") == nil)
        #expect(ini.value(section: "Display", key: "AspectRatio") == nil)
    }

    @Test func shaderArgumentsNeedAPresetExceptToTurnShadersOff() throws {
        #expect(folder.retroArchShaderArguments(for: nil).isEmpty)
        #expect(folder.retroArchShaderArguments(for: SystemSettings.Look.none) == ["--set-shader", ""])
        #expect(folder.retroArchShaderArguments(for: .crt).isEmpty)

        let preset = folder.retroArchShadersDirectory.appending(path: "crt/crt-easymode.slangp")
        try FileManager.default.createDirectory(at: preset.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: preset, atomically: true, encoding: .utf8)
        #expect(folder.retroArchShaderArguments(for: .crt) == ["--set-shader", preset.path])
    }

    @Test func extraArgumentsGoBeforeTheCore() {
        let core = URL(fileURLWithPath: "/cores/snes9x_libretro.dylib")
        let rom = URL(fileURLWithPath: "/roms/game.sfc")
        #expect(RetroArchLauncher.buildArguments(coreDylibURL: core, romURL: rom, extraArguments: ["--set-shader", ""])
            == ["--set-shader", "", "-L", core.path, rom.path])
    }
}
