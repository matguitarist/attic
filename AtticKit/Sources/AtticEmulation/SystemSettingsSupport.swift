import Foundation
import AtticModels

/// What runs a system's games, as far as `SystemSettings` are concerned.
public enum SystemSettingsBackend: Hashable, Sendable {
    case retroArch(coreIdentifier: String)
    case duckStation
    case dolphin
    /// A custom emulator, or one Attic can't configure.
    case other

    public init(catalogEmulatorID: String?) {
        switch catalogEmulatorID {
        case EmulatorCatalog.duckStation.id: self = .duckStation
        case EmulatorCatalog.dolphin.id: self = .dolphin
        default: self = .other
        }
    }
}

/// One row of the System Settings sheet.
public enum SystemSetting: String, CaseIterable, Sendable {
    case look, integerScaling, internalResolution, widescreen, geometryCorrection, unlimitedSprites, lcdColors, runAhead, rewind, resume
}

/// Which `SystemSettings` apply to a system in a given emulator, and how
/// each one translates into that emulator's own settings. Option names and
/// values were read from the cores themselves (their libretro option
/// definitions) and from DuckStation's and Dolphin's settings code.
public enum SystemSettingsSupport {
    // MARK: - What's offered

    /// Systems whose games are 3D: resolution and widescreen matter, and
    /// rewind/run-ahead (which save a state every frame) are too heavy.
    static let threeDSystems: Set<CanonicalSystemID> = [
        .psx, .n64, .saturn, .dreamcast, .naomi, .atomiswave, .ps2, .psp, .nds, .n3ds,
        .gamecube, .wii, .wiiu, .ps3, .xbox, .model3, .triforce
    ]

    public static func settings(for system: CanonicalSystemID, backend: SystemSettingsBackend) -> [SystemSetting] {
        switch backend {
        case .retroArch(let core):
            var settings: [SystemSetting] = [.look, .integerScaling]
            let options = coreOptions[core]
            if options?.resolution != nil { settings.append(.internalResolution) }
            if options?.widescreen != nil { settings.append(.widescreen) }
            if options?.geometryCorrection != nil { settings.append(.geometryCorrection) }
            if options?.unlimitedSprites != nil { settings.append(.unlimitedSprites) }
            if options?.lcdColors != nil { settings.append(.lcdColors) }
            if !threeDSystems.contains(system) { settings += [.runAhead, .rewind] }
            settings.append(.resume)
            return settings
        case .duckStation:
            return [.internalResolution, .widescreen, .geometryCorrection, .rewind]
        case .dolphin:
            return [.internalResolution, .widescreen]
        case .other:
            return []
        }
    }

    /// Resolution multiples offered; the first is the console's own.
    public static func resolutionChoices(for backend: SystemSettingsBackend) -> [Int] {
        switch backend {
        case .retroArch(let core): coreOptions[core]?.resolutionChoices ?? []
        case .duckStation: [1, 2, 3, 4, 5, 6, 8]
        case .dolphin: [1, 2, 3, 4, 5, 6]
        case .other: []
        }
    }

    public static func looks(for system: CanonicalSystemID) -> [SystemSettings.Look] {
        let handheld = SystemTaxonomy.definition(for: system)?.category == .handheld
        return handheld ? [.none, .sharp, .lcd, .crt] : [.none, .sharp, .crt, .crtCurved]
    }

    // MARK: - RetroArch

    /// Shader presets, relative to a slang shader pack's root.
    public static func shaderPreset(for look: SystemSettings.Look) -> String? {
        switch look {
        case .none: nil
        case .sharp: "pixel-art-scaling/sharp-bilinear-simple.slangp"
        case .crt: "crt/crt-easymode.slangp"
        case .crtCurved: "crt/crt-geom.slangp"
        case .lcd: "handheld/lcd-grid-v2.slangp"
        }
    }

    /// RetroArch settings for `--appendconfig`. Keys left out stay as the
    /// user set them in RetroArch (see `EmulationFolder.prepareRetroArchLaunch`).
    public static func retroArchConfig(_ settings: SystemSettings, system: CanonicalSystemID) -> [(key: String, value: String)] {
        var config: [(key: String, value: String)] = []
        let offered = Set(Self.settings(for: system, backend: .retroArch(coreIdentifier: "")))
        if let look = settings.look, look != .none { config.append(("video_shader_enable", "true")) }
        if let integer = settings.integerScaling { config.append(("video_scale_integer", bool(integer))) }
        if offered.contains(.runAhead), let frames = settings.runAheadFrames {
            config.append(("run_ahead_enabled", bool(frames > 0)))
            if frames > 0 {
                config += [("run_ahead_frames", String(frames)), ("run_ahead_secondary_instance", "true")]
            }
        }
        if offered.contains(.rewind), let rewind = settings.rewind { config.append(("rewind_enable", bool(rewind))) }
        if let resume = settings.resume {
            config += [("savestate_auto_save", bool(resume)), ("savestate_auto_load", bool(resume))]
        }
        return config
    }

    /// RetroArch's own defaults, for putting a key back when Attic
    /// stops setting it and never saw the user's value.
    static let retroArchDefaults: [String: String] = [
        "video_shader_enable": "false",
        "video_scale_integer": "false",
        "run_ahead_enabled": "false",
        "run_ahead_frames": "1",
        "run_ahead_secondary_instance": "true",
        "rewind_enable": "false",
        "savestate_auto_save": "false",
        "savestate_auto_load": "false"
    ]

    /// Core options for `core`, set in RetroArch's core options file.
    public static func coreOptions(_ settings: SystemSettings, core: String) -> [String: String] {
        guard let map = coreOptions[core] else { return [:] }
        var options: [String: String] = [:]
        if let scale = settings.internalResolution, let resolution = map.resolution { options.merge(resolution(scale)) { $1 } }
        if let wide = settings.widescreen, let widescreen = map.widescreen { options.merge(widescreen(wide)) { $1 } }
        if let pgxp = settings.geometryCorrection, let geometry = map.geometryCorrection { options.merge(geometry(pgxp)) { $1 } }
        if let unlimited = settings.unlimitedSprites, let sprites = map.unlimitedSprites { options.merge(sprites(unlimited)) { $1 } }
        if let lcd = settings.lcdColors, let colors = map.lcdColors { options.merge(colors(lcd)) { $1 } }
        return options
    }

    /// The core's default for an option Attic stops setting.
    public static func coreOptionDefault(_ key: String) -> String? {
        for map in coreOptions.values {
            if let value = map.defaults[key] { return value }
        }
        return nil
    }

    struct CoreOptionMap {
        var resolutionChoices: [Int] = []
        var resolution: (@Sendable (Int) -> [String: String])?
        var widescreen: (@Sendable (Bool) -> [String: String])?
        var geometryCorrection: (@Sendable (Bool) -> [String: String])?
        var unlimitedSprites: (@Sendable (Bool) -> [String: String])?
        var lcdColors: (@Sendable (Bool) -> [String: String])?
        /// Each option's default, as the core defines it.
        var defaults: [String: String] = [:]
    }

    private static func bool(_ value: Bool) -> String { value ? "true" : "false" }
    private static func enabled(_ value: Bool) -> String { value ? "enabled" : "disabled" }

    private static func spriteLimit(_ key: String) -> CoreOptionMap {
        CoreOptionMap(unlimitedSprites: { [key: enabled($0)] }, defaults: [key: "disabled"])
    }

    static let coreOptions: [String: CoreOptionMap] = [
        // PlayStation
        "swanstation_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 3, 4, 5, 6, 8],
            resolution: { ["swanstation_GPU_ResolutionScale": String($0)] },
            widescreen: { ["swanstation_GPU_WidescreenHack": bool($0), "swanstation_Display_AspectRatio": $0 ? "16:9" : "4:3"] },
            geometryCorrection: { ["swanstation_GPU_PGXPEnable": bool($0)] },
            defaults: [
                "swanstation_GPU_ResolutionScale": "1", "swanstation_GPU_WidescreenHack": "false",
                "swanstation_Display_AspectRatio": "4:3", "swanstation_GPU_PGXPEnable": "false"
            ]
        ),
        "mednafen_psx_hw_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 4, 8],
            resolution: { ["beetle_psx_hw_internal_resolution": $0 == 1 ? "1x(native)" : "\($0)x"] },
            widescreen: { ["beetle_psx_hw_widescreen_hack": enabled($0)] },
            geometryCorrection: { ["beetle_psx_hw_pgxp_mode": $0 ? "memory only" : "disabled"] },
            defaults: [
                "beetle_psx_hw_internal_resolution": "1x(native)", "beetle_psx_hw_widescreen_hack": "disabled",
                "beetle_psx_hw_pgxp_mode": "disabled"
            ]
        ),
        // Nintendo 64: GLideN64 and ParaLLEl-RDP each have their own
        // upscaling option; both are set so it applies whichever runs.
        "mupen64plus_next_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 4, 8],
            resolution: { ["mupen64plus-EnableNativeResFactor": String($0), "mupen64plus-parallel-rdp-upscaling": "\($0)x"] },
            widescreen: { ["mupen64plus-aspect": $0 ? "16:9 adjusted" : "4:3"] },
            defaults: [
                "mupen64plus-EnableNativeResFactor": "0", "mupen64plus-parallel-rdp-upscaling": "1x",
                "mupen64plus-aspect": "4:3"
            ]
        ),
        // Dreamcast, NAOMI, Atomiswave (native 640×480)
        "flycast_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 3, 4],
            resolution: { ["reicast_internal_resolution": "\(640 * $0)x\(480 * $0)"] },
            widescreen: { ["reicast_widescreen_hack": enabled($0)] },
            defaults: ["reicast_internal_resolution": "640x480", "reicast_widescreen_hack": "disabled"]
        ),
        // PlayStation 2: the widescreen hint applies PCSX2's built-in
        // widescreen patches.
        "pcsx2_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 4, 8],
            resolution: { ["pcsx2_upscale_multiplier": $0 == 1 ? "1x (Native)" : "\($0)x"] },
            widescreen: { ["pcsx2_widescreen_hint": $0 ? "enabled (16:9)" : "disabled"] },
            defaults: ["pcsx2_upscale_multiplier": "1x (Native)", "pcsx2_widescreen_hint": "disabled"]
        ),
        // PSP (native 480×272)
        "ppsspp_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 3, 4, 5],
            resolution: { ["ppsspp_internal_resolution": "\(480 * $0)x\(272 * $0)"] },
            defaults: ["ppsspp_internal_resolution": "480x272"]
        ),
        "dolphin_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 3, 4, 5, 6],
            resolution: { ["dolphin_efb_scale": String($0)] },
            widescreen: { ["dolphin_widescreen_hack": enabled($0)] },
            defaults: ["dolphin_efb_scale": "1", "dolphin_widescreen_hack": "disabled"]
        ),
        "azahar_libretro": CoreOptionMap(
            resolutionChoices: [1, 2, 3, 4, 5, 6],
            resolution: { ["citra_resolution_factor": String($0)] },
            defaults: ["citra_resolution_factor": "1"]
        ),
        // Sprite limits
        "mesen_libretro": spriteLimit("mesen_nospritelimit"),
        "nestopia_libretro": spriteLimit("nestopia_nospritelimit"),
        "fceumm_libretro": spriteLimit("fceumm_nospritelimit"),
        "genesis_plus_gx_libretro": spriteLimit("genesis_plus_gx_no_sprite_limit"),
        "picodrive_libretro": spriteLimit("picodrive_sprlim"),
        "mednafen_pce_libretro": spriteLimit("pce_nospritelimit"),
        // Game Boy Advance
        "mgba_libretro": CoreOptionMap(
            lcdColors: { ["mgba_color_correction": $0 ? "Auto" : "OFF", "mgba_interframe_blending": $0 ? "mix_smart" : "OFF"] },
            defaults: ["mgba_color_correction": "OFF", "mgba_interframe_blending": "OFF"]
        )
    ]

    // MARK: - DuckStation

    /// DuckStation settings (section, key, value), or `nil` as the value
    /// for one Attic stops setting.
    public static func duckStationSettings(_ settings: SystemSettings) -> [(section: String, key: String, value: String?)] {
        [
            ("GPU", "ResolutionScale", settings.internalResolution.map(String.init)),
            ("GPU", "WidescreenHack", settings.widescreen.map(bool)),
            ("Display", "AspectRatio", settings.widescreen.map { $0 ? "16:9" : "Auto (Game Native)" }),
            ("GPU", "PGXPEnable", settings.geometryCorrection.map(bool)),
            ("Main", "RewindEnable", settings.rewind.map(bool))
        ]
    }

    // MARK: - Dolphin

    /// Dolphin's `-C` overrides apply to that one run and are never saved.
    public static func dolphinArguments(_ settings: SystemSettings) -> [String] {
        var arguments: [String] = []
        if let scale = settings.internalResolution {
            arguments += ["-C", "GFX.Settings.InternalResolution=\(scale)"]
        }
        if let wide = settings.widescreen {
            arguments += ["-C", "GFX.Settings.wideScreenHack=\(wide ? "True" : "False")"]
        }
        return arguments
    }
}
