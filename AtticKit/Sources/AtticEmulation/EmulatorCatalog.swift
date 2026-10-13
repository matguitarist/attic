import Foundation
import AtticModels

/// A RetroArch core Attic knows how to install, from libretro's official
/// buildbot — the same source RetroArch's own Online Updater downloads
/// from. Nothing is bundled with Attic itself.
public struct RecommendedCore: Sendable, Hashable, Identifiable {
    /// Matches the dylib's filename without extension, e.g.
    /// "snes9x_libretro" — the same identifier `RetroArchCoreInfo` and
    /// `LaunchTargetReference.retroArchCore` use.
    public let coreIdentifier: String
    public let displayName: String
    /// One line on why you'd pick this core over the others.
    public let summary: String

    public var id: String { coreIdentifier }

    public init(_ coreIdentifier: String, _ displayName: String, _ summary: String) {
        self.coreIdentifier = coreIdentifier
        self.displayName = displayName
        self.summary = summary
    }
}

/// A standalone (non-RetroArch) emulator that's the better choice for some
/// systems, installed from the project's official GitHub release.
public struct StandaloneEmulator: Sendable, Hashable, Identifiable {
    public enum Archive: Sendable, Hashable {
        /// A .zip containing the .app at its root.
        case zip
        /// `downloadURL` is Dolphin's release feed (JSON); the macOS disk
        /// image it links to is downloaded and the .app copied off it.
        case dolphinReleaseFeed
        /// `downloadURL` is a GitHub "latest release" API URL; the asset
        /// whose name ends with the suffix is downloaded (.zip, .dmg, .7z
        /// or .tar.xz). A `*` in it stands for a version.
        case githubRelease(assetSuffix: String)
    }

    public let id: String
    public let name: String
    public let summary: String
    /// The `.app` bundle name inside the archive and once installed.
    /// For an emulator shipped as a bare binary, the folder it's
    /// installed as instead (no `.app`): the archive's contents.
    public let appBundleName: String
    /// Path of the launch binary inside the bundle.
    public let executableRelativePath: String
    /// Passed to `ArgumentTemplate`, so it uses the same placeholders as
    /// user-made custom emulator profiles.
    public let argumentTemplate: String
    public let downloadURL: URL
    public let archive: Archive
    public let homepageURL: URL
    public let license: String
    public let systems: [CanonicalSystemID]
    /// How to keep this emulator's data inside the Emulation folder, when
    /// it supports that. `nil` means it keeps its data in ~/Library.
    public let portableHome: PortableHome?
}

/// Keeps a standalone emulator's data in `Emulation/Config/<Name>` by
/// launching it with `HOME` pointed there, then pre-filling its settings
/// file so BIOS, saves and states land in the shared Emulation folders.
///
/// (DuckStation's own `portable.txt` mode was tried and rejected: on macOS
/// it only works from inside the .app bundle and stores everything there,
/// so updating the app would delete memory cards and settings.)
public struct PortableHome: Sendable, Hashable {
    public struct Setting: Sendable, Hashable {
        public let section: String
        public let key: String
        /// May contain `{bios}`, `{saves}` and `{states}` — the latter two
        /// resolve to the launched game's per-system folders.
        public let value: String
        /// Defaults (e.g. controller mappings) are only filled in when
        /// absent, so changes the user makes in the emulator stick; paths
        /// are rewritten every launch to follow the Emulation folder.
        public let onlyIfMissing: Bool

        public init(_ section: String, _ key: String, _ value: String, onlyIfMissing: Bool = false) {
            self.section = section
            self.key = key
            self.value = value
            self.onlyIfMissing = onlyIfMissing
        }
    }

    /// The settings file, relative to the redirected HOME.
    public let settingsRelativePath: String
    public let settings: [Setting]
    /// Bound when "Quit games with Select + Start" is on; removed again
    /// (only if still Attic's value) when it's turned off.
    public var quitComboSettings: [Setting] = []

    /// Where the emulator keeps player 1's button bindings, so Attic's
    /// button mapping can be applied to it. Keys are named by
    /// `RetroPadButton.duckStationName`; values are `prefix` + the SDL
    /// button name.
    public struct PadBindings: Sendable, Hashable {
        public let section: String
        public let prefix: String
    }
    public var padBindings: PadBindings?
}

/// A BIOS/firmware file a system needs. These are copyrighted and must be
/// dumped from hardware the user owns, so Attic only *checks* for them
/// and says where they go — it never downloads them.
public struct BIOSRequirement: Sendable, Hashable {
    public let fileName: String
    public let required: Bool
    public let note: String?
    /// Cores that run without this file (they have a built-in replacement),
    /// for which a required file is only optional.
    public let notNeededBy: Set<String>
    /// For a folder requirement: dumps known to work, by their usual file
    /// names, so the user knows what to look for.
    public let supportedDumps: [String]

    public init(_ fileName: String, required: Bool = true, note: String? = nil, notNeededBy: Set<String> = [], supportedDumps: [String] = []) {
        self.fileName = fileName
        self.required = required
        self.note = note
        self.notNeededBy = notNeededBy
        self.supportedDumps = supportedDumps
    }

    /// A name ending in "/" is a folder the emulator scans for any dump
    /// (PCSX2 takes whichever PS2 BIOS it finds there).
    public var isFolder: Bool { fileName.hasSuffix("/") }

    /// The folder this file goes in: BIOS/ itself for most, a subfolder
    /// like BIOS/dc or BIOS/pcsx2/bios for some.
    public func folder(in biosDirectory: URL) -> URL {
        let url = biosDirectory.appending(path: fileName)
        return isFolder ? url : url.deletingLastPathComponent()
    }

    public func isPresent(in biosDirectory: URL) -> Bool {
        let url = biosDirectory.appending(path: fileName)
        guard isFolder else { return FileManager.default.fileExists(atPath: url.path) }
        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
        return entries.contains { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

/// Everything Attic recommends for running one system.
public struct SystemEmulatorRecommendation: Sendable, Hashable {
    public let systemID: CanonicalSystemID
    /// Best first. The first entry is what "Set Up" installs.
    public let cores: [RecommendedCore]
    public let standalone: [StandaloneEmulator]
    /// BIOS files for the *recommended* core, which RetroArch looks for in
    /// its system directory.
    public let bios: [BIOSRequirement]
    /// When set, the standalone emulator is the better pick and the UI
    /// should lead with it — the core stays available as an alternative.
    public let prefersStandalone: Bool

    public var recommendedCore: RecommendedCore? { cores.first }

    /// The BIOS files as `coreIdentifier` needs them: required ones it has
    /// its own replacement for become optional. Unknown or no core (a
    /// standalone emulator) keeps the list as is.
    public func bios(forCore coreIdentifier: String?) -> [BIOSRequirement] {
        guard let coreIdentifier else { return bios }
        return bios.map { requirement in
            guard requirement.required, requirement.notNeededBy.contains(coreIdentifier) else { return requirement }
            let core = cores.first { $0.coreIdentifier == coreIdentifier }?.displayName ?? coreIdentifier
            let notNeeded = String(localized: "Not needed by \(core)", bundle: .module)
            return BIOSRequirement(requirement.fileName, required: false,
                                   note: [requirement.note, notNeeded].compactMap { $0 }.joined(separator: " · "),
                                   supportedDumps: requirement.supportedDumps)
        }
    }
}

/// The curated table behind Attic's emulator setup. Choices favor
/// accuracy where Apple Silicon handles it comfortably, and every core here
/// was confirmed present on the arm64 macOS buildbot.
public enum EmulatorCatalog {
    public static let buildbotCoresURL = URL(string: "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/")!
    /// Every core's `.info` file in one archive — Attic needs these to
    /// know which system a core runs and which file extensions it takes.
    public static let coreInfoArchiveURL = URL(string: "https://buildbot.libretro.com/assets/frontend/info.zip")!
    public static let retroArchStableIndexURL = URL(string: "https://buildbot.libretro.com/stable/")!
    public static let retroArchHomepageURL = URL(string: "https://www.retroarch.com")!
    /// libretro's slang shader pack, the one RetroArch's Online Updater
    /// installs, for System Settings' looks (Sharp, CRT, LCD).
    public static let slangShadersURL = URL(string: "https://buildbot.libretro.com/assets/frontend/shaders_slang.zip")!

    /// CRC32 per core, the same file RetroArch's Online Updater reads to
    /// decide whether a core is current.
    public static let buildbotCoreChecksumsURL = buildbotCoresURL.appending(path: ".index-extended")

    /// libretro's downloadable "core system files", by core.
    public static let coreSystemFiles: [String: String] = [
        "ppsspp_libretro": "PPSSPP.zip",
        "dolphin_libretro": "Dolphin.zip",
        "pcsx2_libretro": "LRPS2.zip",
        "bluemsx_libretro": "blueMSX.zip",
        "scummvm_libretro": "ScummVM.zip",
        "prboom_libretro": "PrBoom.zip"
    ]

    public static func systemFilesURL(_ archiveName: String) -> URL {
        URL(string: "https://buildbot.libretro.com/assets/system/")!.appending(path: archiveName)
    }

    public static func coreDownloadURL(for coreIdentifier: String) -> URL {
        buildbotCoresURL.appending(path: "\(coreIdentifier).dylib.zip")
    }

    /// The Metal build is the one libretro recommends for Apple Silicon.
    public static func retroArchDownloadURL(version: String) -> URL {
        retroArchStableIndexURL.appending(path: "\(version)/apple/osx/universal/RetroArch_Metal.dmg")
    }

    // MARK: - Standalone emulators

    public static let duckStation = StandaloneEmulator(
        id: "duckstation",
        name: "DuckStation",
        summary: String(localized: "The most accurate and polished PlayStation emulator, with upscaling and per-game fixes.", bundle: .module),
        appBundleName: "DuckStation.app",
        executableRelativePath: "Contents/MacOS/DuckStation",
        argumentTemplate: "-batch -nogui -fullscreen {romPath}",
        downloadURL: URL(string: "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-mac-release.zip")!,
        archive: .zip,
        homepageURL: URL(string: "https://www.duckstation.org")!,
        license: "CC BY-NC-ND 4.0",
        systems: [.psx],
        // Verified against the real app: with HOME redirected, DuckStation
        // creates its whole data directory under it and never touches
        // ~/Library — but only if Library/Application Support already exists.
        portableHome: PortableHome(
            settingsRelativePath: "Library/Application Support/DuckStation/settings.ini",
            settings: [
                .init("Main", "SetupWizardIncomplete", "false"),
                .init("Main", "ConfirmPowerOff", "false"),
                .init("BIOS", "SearchDirectory", "{bios}"),
                .init("MemoryCards", "Directory", "{saves}"),
                .init("Folders", "SaveStates", "{states}")
            ] + duckStationControllerDefaults,
            quitComboSettings: [
                // DuckStation chords use " & "; PowerOff in -batch mode exits.
                .init("Hotkeys", "PowerOff", "SDL-0/Back & SDL-0/Start")
            ],
            padBindings: .init(section: "Pad1", prefix: "SDL-0/")
        )
    )

    // Dreamcast deliberately has no standalone entry: the Flycast core is
    // the same emulator, and as a core its config, saves and states live in
    // the Emulation folder like every other RetroArch system — the
    // standalone app keeps its settings in ~/Library.
    /// What DuckStation's setup wizard would map automatically for the
    /// first SDL game controller (copied from a wizard-configured install).
    /// Attic skips the wizard, and without these the controller does
    /// nothing in game.
    private static let duckStationControllerDefaults: [PortableHome.Setting] = [
        .init("InputSources", "SDL", "true", onlyIfMissing: true),
        .init("Pad1", "Type", "AnalogController", onlyIfMissing: true)
    ] + [
        ("Up", "DPadUp"), ("Down", "DPadDown"), ("Left", "DPadLeft"), ("Right", "DPadRight"),
        ("Cross", "A"), ("Circle", "B"), ("Square", "X"), ("Triangle", "Y"),
        ("Select", "Back"), ("Start", "Start"), ("Analog", "Guide"),
        ("L1", "LeftShoulder"), ("R1", "RightShoulder"),
        ("L2", "+LeftTrigger"), ("R2", "+RightTrigger"),
        ("L3", "LeftStick"), ("R3", "RightStick"),
        ("LUp", "-LeftY"), ("LDown", "+LeftY"), ("LLeft", "-LeftX"), ("LRight", "+LeftX"),
        ("RUp", "-RightY"), ("RDown", "+RightY"), ("RLeft", "-RightX"), ("RRight", "+RightX"),
        ("LargeMotor", "LargeMotor"), ("SmallMotor", "SmallMotor")
    ].map { PortableHome.Setting("Pad1", $0.0, "SDL-0/\($0.1)", onlyIfMissing: true) }

    /// Triforce support was merged into mainline Dolphin, so the regular
    /// release runs both GameCube and Triforce games. No `portableHome`:
    /// Dolphin keeps its data in ~/Library/Application Support/Dolphin,
    /// where any controller setup made in Dolphin itself already lives.
    public static let dolphin = StandaloneEmulator(
        id: "dolphin",
        name: "Dolphin",
        summary: String(localized: "The GameCube and Wii emulator, which also runs Triforce arcade games.", bundle: .module),
        appBundleName: "Dolphin.app",
        executableRelativePath: "Contents/MacOS/Dolphin",
        // -b exits Dolphin when the game stops; -C overrides a setting for
        // this run only, without saving it.
        argumentTemplate: "-b -C Dolphin.Display.Fullscreen=True -e {romPath}",
        downloadURL: URL(string: "https://dolphin-emu.org/update/latest/beta/")!,
        archive: .dolphinReleaseFeed,
        homepageURL: URL(string: "https://dolphin-emu.org")!,
        license: "GPL-2.0-or-later",
        systems: [.gamecube, .wii, .triforce],
        portableHome: nil
    )

    public static let xemu = StandaloneEmulator(
        id: "xemu",
        name: "xemu",
        summary: String(localized: "The original Xbox emulator.", bundle: .module),
        appBundleName: "xemu.app",
        executableRelativePath: "Contents/MacOS/xemu",
        argumentTemplate: "-full-screen -dvd_path {romPath}",
        downloadURL: URL(string: "https://api.github.com/repos/xemu-project/xemu/releases/latest")!,
        archive: .githubRelease(assetSuffix: "-macos-universal.zip"),
        homepageURL: URL(string: "https://xemu.app")!,
        license: "GPL-2.0",
        systems: [.xbox],
        portableHome: nil
    )

    /// PCSX2's Mac build is Intel-only, so it runs through Rosetta; the
    /// core runs natively and stays the first pick. Its release archive
    /// names the app with its version ("PCSX2-v2.8.2.app"); it's installed
    /// as PCSX2.app. Verified against the real app: with HOME redirected,
    /// all its data goes under it.
    public static let pcsx2 = StandaloneEmulator(
        id: "pcsx2",
        name: "PCSX2",
        summary: String(localized: "The PS2 emulator's own app. Intel-only, so it runs through Rosetta.", bundle: .module),
        appBundleName: "PCSX2.app",
        executableRelativePath: "Contents/MacOS/PCSX2",
        argumentTemplate: "-batch -nogui -fullscreen -- {romPath}",
        downloadURL: URL(string: "https://api.github.com/repos/PCSX2/pcsx2/releases/latest")!,
        archive: .githubRelease(assetSuffix: "-macos-Qt.tar.xz"),
        homepageURL: URL(string: "https://pcsx2.net")!,
        license: "GPL-3.0",
        systems: [.ps2],
        portableHome: PortableHome(
            settingsRelativePath: "Library/Application Support/PCSX2/inis/PCSX2.ini",
            settings: [
                .init("UI", "SetupWizardIncomplete", "false"),
                .init("UI", "ConfirmShutdown", "false"),
                // The same folder the PCSX2 core reads, so one dump serves both.
                .init("Folders", "Bios", "{bios}/pcsx2/bios"),
                .init("Folders", "MemoryCards", "{saves}"),
                .init("Folders", "Savestates", "{states}"),
                .init("InputSources", "SDL", "true", onlyIfMissing: true)
            ] + pcsx2ControllerDefaults,
            quitComboSettings: [
                // In -batch mode, shutting down exits PCSX2.
                .init("Hotkeys", "ShutdownVM", "SDL-0/Back & SDL-0/Start")
            ]
        )
    )

    /// Player 1 on the first SDL controller (PCSX2's own defaults are
    /// keyboard keys). PCSX2 names SDL buttons by position: FaceSouth is
    /// A on an Xbox pad, Cross on a PlayStation one.
    private static let pcsx2ControllerDefaults: [PortableHome.Setting] = [
        .init("Pad1", "Type", "DualShock2", onlyIfMissing: true)
    ] + [
        ("Up", "DPadUp"), ("Down", "DPadDown"), ("Left", "DPadLeft"), ("Right", "DPadRight"),
        ("Cross", "FaceSouth"), ("Circle", "FaceEast"), ("Square", "FaceWest"), ("Triangle", "FaceNorth"),
        ("Select", "Back"), ("Start", "Start"), ("Analog", "Guide"),
        ("L1", "LeftShoulder"), ("R1", "RightShoulder"),
        ("L2", "+LeftTrigger"), ("R2", "+RightTrigger"),
        ("L3", "LeftStick"), ("R3", "RightStick"),
        ("LUp", "-LeftY"), ("LDown", "+LeftY"), ("LLeft", "-LeftX"), ("LRight", "+LeftX"),
        ("RUp", "-RightY"), ("RDown", "+RightY"), ("RLeft", "-RightX"), ("RRight", "+RightX"),
        ("LargeMotor", "LargeMotor"), ("SmallMotor", "SmallMotor")
    ].map { PortableHome.Setting("Pad1", $0.0, "SDL-0/\($0.1)", onlyIfMissing: true) }

    public static let rpcs3 = StandaloneEmulator(
        id: "rpcs3",
        name: "RPCS3",
        summary: String(localized: "The PlayStation 3 emulator, native on Apple Silicon.", bundle: .module),
        appBundleName: "RPCS3.app",
        executableRelativePath: "Contents/MacOS/rpcs3",
        argumentTemplate: "--no-gui --fullscreen {romPath}",
        downloadURL: URL(string: "https://api.github.com/repos/RPCS3/rpcs3-binaries-mac-arm64/releases/latest")!,
        archive: .githubRelease(assetSuffix: "_macos_aarch64.7z"),
        homepageURL: URL(string: "https://rpcs3.net")!,
        license: "GPL-2.0",
        systems: [.ps3],
        portableHome: nil
    )

    /// Native on Apple Silicon. Games are installed into it (its own
    /// data stays in ~/Library) and run by title ID, from a `.psvita` file
    /// holding it; the SDL frontend is a plain window that quits with the
    /// game.
    public static let vita3K = StandaloneEmulator(
        id: "vita3k",
        name: "Vita3K",
        summary: String(localized: "The PS Vita emulator, native on Apple Silicon.", bundle: .module),
        appBundleName: "Vita3K.app",
        executableRelativePath: "Contents/MacOS/Vita3K",
        argumentTemplate: "--frontend sdl -F -r {titleID}",
        downloadURL: URL(string: "https://api.github.com/repos/Vita3K/Vita3K/releases/latest")!,
        archive: .githubRelease(assetSuffix: "macos-arm64-latest.dmg"),
        homepageURL: URL(string: "https://vita3k.org")!,
        license: "GPL-2.0",
        systems: [.psvita],
        portableHome: nil
    )

    /// A bare Intel binary (with its Vulkan libraries) rather than an app,
    /// so it runs through Rosetta and installs as a folder. It keeps its
    /// data in ~/Library/Application Support/shadPS4 whatever HOME says.
    public static let shadPS4 = StandaloneEmulator(
        id: "shadps4",
        name: "shadPS4",
        summary: String(localized: "The PS4 emulator. Early days: many games don't run yet. Intel-only, so it runs through Rosetta.", bundle: .module),
        appBundleName: "shadPS4",
        executableRelativePath: "shadps4",
        argumentTemplate: "--fullscreen true -g {romPath}/eboot.bin",
        downloadURL: URL(string: "https://api.github.com/repos/shadps4-emu/shadPS4/releases/latest")!,
        archive: .githubRelease(assetSuffix: "macos-sdl-*.zip"),
        homepageURL: URL(string: "https://shadps4.net")!,
        license: "GPL-2.0",
        systems: [.ps4],
        portableHome: nil
    )

    public static let standaloneEmulators: [StandaloneEmulator] = [duckStation, dolphin, xemu, rpcs3, pcsx2, vita3K, shadPS4]

    // MARK: - Per-system table

    private static let genesisPlusGX = RecommendedCore("genesis_plus_gx_libretro", "Genesis Plus GX", String(localized: "Highly accurate Sega 8/16-bit and Sega CD.", bundle: .module))
    private static let picoDrive = RecommendedCore("picodrive_libretro", "PicoDrive", String(localized: "Fast; the only option with 32X support.", bundle: .module))
    // Shared by several systems below.
    private static let gambatte = RecommendedCore("gambatte_libretro", "Gambatte", String(localized: "Accurate and light — the usual Game Boy choice.", bundle: .module))
    private static let sameBoy = RecommendedCore("sameboy_libretro", "SameBoy", String(localized: "The most accurate Game Boy core.", bundle: .module))
    private static let gearboy = RecommendedCore("gearboy_libretro", "Gearboy", String(localized: "Fast, with Super Game Boy support.", bundle: .module))
    private static let flycast = RecommendedCore("flycast_libretro", "Flycast", String(localized: "Dreamcast, NAOMI and Atomiswave, with upscaling.", bundle: .module))
    private static let beetleWonderSwan = RecommendedCore("mednafen_wswan_libretro", "Beetle WonderSwan", String(localized: "Accurate WonderSwan and WonderSwan Color.", bundle: .module))
    private static let beetleNGP = RecommendedCore("mednafen_ngp_libretro", "Beetle NeoPop", String(localized: "Accurate Neo Geo Pocket and Pocket Color.", bundle: .module))
    private static let race = RecommendedCore("race_libretro", "RACE", String(localized: "Lighter Neo Geo Pocket core.", bundle: .module))
    private static let dolphinCore = RecommendedCore("dolphin_libretro", "Dolphin", String(localized: "Dolphin as a RetroArch core; the standalone app is more complete.", bundle: .module))
    private static let fbneo = RecommendedCore("fbneo_libretro", "FinalBurn Neo", String(localized: "The reference Neo Geo and arcade emulator.", bundle: .module))
    private static let mameCurrent = RecommendedCore("mame_libretro", "MAME", String(localized: "Current MAME; needs romsets from the same MAME version.", bundle: .module))
    private static let beetlePCE = RecommendedCore("mednafen_pce_libretro", "Beetle PCE", String(localized: "Accurate PC Engine, CD and SuperGrafx.", bundle: .module))
    private static let beetlePCEFast = RecommendedCore("mednafen_pce_fast_libretro", "Beetle PCE Fast", String(localized: "Lighter PC Engine core.", bundle: .module))

    public static let recommendations: [SystemEmulatorRecommendation] = [
        .init(systemID: .nes, cores: [
            RecommendedCore("mesen_libretro", "Mesen", String(localized: "Most accurate NES core.", bundle: .module)),
            RecommendedCore("nestopia_libretro", "Nestopia UE", String(localized: "Accurate and lighter.", bundle: .module)),
            RecommendedCore("fceumm_libretro", "FCEUmm", String(localized: "Fast, broad mapper support.", bundle: .module))
        ], standalone: [], bios: [], prefersStandalone: false),

        .init(systemID: .snes, cores: [
            RecommendedCore("snes9x_libretro", "Snes9x", String(localized: "Accurate and fast — the usual choice.", bundle: .module)),
            RecommendedCore("bsnes_libretro", "bsnes", String(localized: "Cycle-accurate; heavier.", bundle: .module))
        ], standalone: [], bios: [], prefersStandalone: false),

        // Snes9x is the core that reads BS-X and Sufami Turbo cartridges.
        .init(systemID: .satellaview, cores: [
            RecommendedCore("snes9x_libretro", "Snes9x", String(localized: "Plays Satellaview broadcasts through the BS-X BIOS.", bundle: .module))
        ], standalone: [], bios: [BIOSRequirement("BS-X.bin", note: "BS-X Japan, Rev 1")], prefersStandalone: false),
        .init(systemID: .sufami, cores: [
            RecommendedCore("snes9x_libretro", "Snes9x", String(localized: "Plays SuFami Turbo cartridges through its BIOS.", bundle: .module))
        ], standalone: [], bios: [BIOSRequirement("STBIOS.bin")], prefersStandalone: false),

        .init(systemID: .genesis, cores: [genesisPlusGX, picoDrive], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .mastersystem, cores: [genesisPlusGX, picoDrive], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .gamegear, cores: [genesisPlusGX, picoDrive], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .segacd, cores: [genesisPlusGX, picoDrive], standalone: [], bios: [
            BIOSRequirement("bios_CD_U.bin", note: "US"),
            BIOSRequirement("bios_CD_E.bin", required: false, note: "Europe"),
            BIOSRequirement("bios_CD_J.bin", required: false, note: "Japan")
        ], prefersStandalone: false),
        .init(systemID: .sega32x, cores: [picoDrive], standalone: [], bios: [], prefersStandalone: false),

        .init(systemID: .psx, cores: [
            RecommendedCore("swanstation_libretro", "SwanStation", String(localized: "DuckStation's engine as a RetroArch core.", bundle: .module)),
            RecommendedCore("mednafen_psx_hw_libretro", "Beetle PSX HW", String(localized: "Very accurate, with upscaling.", bundle: .module)),
            RecommendedCore("pcsx_rearmed_libretro", "PCSX ReARMed", String(localized: "Fast; can run without a BIOS.", bundle: .module))
        ], standalone: [duckStation], bios: [
            BIOSRequirement("scph5501.bin", note: "US", notNeededBy: ["pcsx_rearmed_libretro"]),
            BIOSRequirement("scph5502.bin", required: false, note: "Europe"),
            BIOSRequirement("scph5500.bin", required: false, note: "Japan")
        ], prefersStandalone: true),

        .init(systemID: .gba, cores: [
            RecommendedCore("mgba_libretro", "mGBA", String(localized: "Accurate and fast — the standard GBA core.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("gba_bios.bin", required: false, note: "Optional; improves accuracy")
        ], prefersStandalone: false),

        .init(systemID: .saturn, cores: [
            RecommendedCore("mednafen_saturn_libretro", "Beetle Saturn", String(localized: "Most accurate Saturn core.", bundle: .module)),
            RecommendedCore("yabasanshiro_libretro", "YabaSanshiro", String(localized: "Faster, less accurate.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("sega_101.bin", required: false, note: "Japan; for Japanese games"),
            BIOSRequirement("mpr-17933.bin", note: "US/Europe", notNeededBy: ["yabasanshiro_libretro"])
        ], prefersStandalone: false),

        .init(systemID: .dreamcast, cores: [
            RecommendedCore("flycast_libretro", "Flycast", String(localized: "The Dreamcast core.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("dc/dc_boot.bin", required: false, note: "Optional; Flycast can boot most games without it")
        ], prefersStandalone: false),

        .init(systemID: .atari2600, cores: [
            RecommendedCore("stella_libretro", "Stella", String(localized: "The reference Atari 2600 emulator.", bundle: .module))
        ], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .atari5200, cores: [
            RecommendedCore("a5200_libretro", "a5200", String(localized: "Dedicated 5200 core.", bundle: .module)),
            RecommendedCore("atari800_libretro", "Atari800", String(localized: "Atari 8-bit family including 5200.", bundle: .module))
        ], standalone: [], bios: [BIOSRequirement("5200.rom")], prefersStandalone: false),
        .init(systemID: .atari7800, cores: [
            RecommendedCore("prosystem_libretro", "ProSystem", String(localized: "The Atari 7800 core.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("7800 BIOS (U).rom", required: false, note: "Optional")
        ], prefersStandalone: false),
        .init(systemID: .atarilynx, cores: [
            RecommendedCore("handy_libretro", "Handy", String(localized: "The reference Lynx emulator.", bundle: .module)),
            RecommendedCore("mednafen_lynx_libretro", "Beetle Lynx", String(localized: "Mednafen's Lynx core.", bundle: .module))
        ], standalone: [], bios: [BIOSRequirement("lynxboot.img")], prefersStandalone: false),
        .init(systemID: .atarijaguar, cores: [
            RecommendedCore("virtualjaguar_libretro", "Virtual Jaguar", String(localized: "The only Jaguar core.", bundle: .module))
        ], standalone: [], bios: [], prefersStandalone: false),

        .init(systemID: .pcengine, cores: [beetlePCE, beetlePCEFast], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .pcenginecd, cores: [beetlePCE, beetlePCEFast], standalone: [], bios: [
            BIOSRequirement("syscard3.pce", note: "System Card 3.0")
        ], prefersStandalone: false),
        .init(systemID: .supergrafx, cores: [
            RecommendedCore("mednafen_supergrafx_libretro", "Beetle SuperGrafx", String(localized: "Dedicated SuperGrafx core.", bundle: .module)),
            beetlePCE
        ], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .pcfx, cores: [
            RecommendedCore("mednafen_pcfx_libretro", "Beetle PC-FX", String(localized: "The only PC-FX core.", bundle: .module))
        ], standalone: [], bios: [BIOSRequirement("pcfx.rom")], prefersStandalone: false),

        .init(systemID: .threedo, cores: [
            RecommendedCore("opera_libretro", "Opera", String(localized: "The 3DO core.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("panafz10.bin", note: "Panasonic FZ-10; other 3DO BIOS revisions also work")
        ], prefersStandalone: false),
        .init(systemID: .virtualboy, cores: [
            RecommendedCore("mednafen_vb_libretro", "Beetle VB", String(localized: "The Virtual Boy core.", bundle: .module))
        ], standalone: [], bios: [], prefersStandalone: false),

        // FinalBurn Neo's info file lists only its generic arcade database,
        // so the Neo Geo mapping comes from this table.
        .init(systemID: .neogeo, cores: [
            fbneo,
            RecommendedCore("geolith_libretro", "Geolith", String(localized: "Neo Geo only, highly accurate.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("neogeo.zip")
        ], prefersStandalone: false),
        // FinalBurn Neo's info file names only its generic arcade database,
        // so these mappings also come from this table. Its romsets track
        // current MAME's for these boards, which is what most CPS sets are.
        .init(systemID: .cps1, cores: [fbneo, mameCurrent], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .cps2, cores: [fbneo, mameCurrent], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .cps3, cores: [fbneo, mameCurrent], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .gb, cores: [gambatte, sameBoy, gearboy], standalone: [], bios: [BIOSRequirement("gb_bios.bin", required: false, note: "Optional; shows the boot logo")], prefersStandalone: false),
        .init(systemID: .gbc, cores: [gambatte, sameBoy, gearboy], standalone: [], bios: [BIOSRequirement("gbc_bios.bin", required: false, note: "Optional; shows the boot logo")], prefersStandalone: false),
        .init(systemID: .n64, cores: [RecommendedCore("mupen64plus_next_libretro", "Mupen64Plus-Next", String(localized: "Best compatibility, with upscaling.", bundle: .module)), RecommendedCore("parallel_n64_libretro", "ParaLLEl N64", String(localized: "Alternative N64 core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .n64dd, cores: [
            RecommendedCore("mupen64plus_next_libretro", "Mupen64Plus-Next", String(localized: "Reads 64DD disks with the 64DD IPL.", bundle: .module)),
            RecommendedCore("parallel_n64_libretro", "ParaLLEl N64", String(localized: "Also reads 64DD disks, from its own copy of the IPL.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("Mupen64plus/IPL.n64", note: "64DD IPL, for Mupen64Plus-Next", notNeededBy: ["parallel_n64_libretro"]),
            BIOSRequirement("64DD_IPL.bin", note: "The same IPL, for ParaLLEl N64", notNeededBy: ["mupen64plus_next_libretro"])
        ], prefersStandalone: false),
        .init(systemID: .nds, cores: [RecommendedCore("melondsds_libretro", "melonDS DS", String(localized: "Accurate DS and DSi, no BIOS needed.", bundle: .module)), RecommendedCore("desmume_libretro", "DeSmuME", String(localized: "Older, widely compatible DS core.", bundle: .module))], standalone: [], bios: [BIOSRequirement("bios7.bin", required: false, note: "Optional; melonDS DS has a built-in replacement"), BIOSRequirement("bios9.bin", required: false, note: "Optional"), BIOSRequirement("firmware.bin", required: false, note: "Optional")], prefersStandalone: false),
        .init(systemID: .n3ds, cores: [RecommendedCore("azahar_libretro", "Azahar", String(localized: "Citra's actively developed successor.", bundle: .module)), RecommendedCore("panda3ds_libretro", "Panda3DS", String(localized: "Newer, lighter 3DS core.", bundle: .module)), RecommendedCore("citra_libretro", "Citra", String(localized: "The original 3DS core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .gamecube, cores: [dolphinCore], standalone: [dolphin], bios: [], prefersStandalone: true),
        .init(systemID: .wii, cores: [dolphinCore], standalone: [dolphin], bios: [], prefersStandalone: true),
        .init(systemID: .wiiu, cores: [RecommendedCore("cemu_libretro", "Cemu", String(localized: "The Wii U emulator, as a RetroArch core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .fds, cores: [RecommendedCore("fceumm_libretro", "FCEUmm", String(localized: "Famicom Disk System support built in.", bundle: .module)), RecommendedCore("mesen_libretro", "Mesen", String(localized: "Most accurate NES core, with disk support.", bundle: .module))], standalone: [], bios: [BIOSRequirement("disksys.rom", note: "Famicom Disk System BIOS")], prefersStandalone: false),
        .init(systemID: .pokemini, cores: [RecommendedCore("pokemini_libretro", "PokeMini", String(localized: "The Pokémon Mini core.", bundle: .module))], standalone: [], bios: [BIOSRequirement("bios.min", required: false, note: "Optional; a free replacement is built in")], prefersStandalone: false),
        .init(systemID: .gameandwatch, cores: [RecommendedCore("gw_libretro", "Game & Watch", String(localized: "Plays Game & Watch .mgw files.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .sg1000, cores: [genesisPlusGX, RecommendedCore("gearsystem_libretro", "Gearsystem", String(localized: "Accurate Sega 8-bit core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .naomi, cores: [flycast], standalone: [], bios: [BIOSRequirement("dc/naomi.zip")], prefersStandalone: false),
        .init(systemID: .atomiswave, cores: [flycast], standalone: [], bios: [BIOSRequirement("dc/awbios.zip")], prefersStandalone: false),
        .init(systemID: .naomi2, cores: [flycast], standalone: [], bios: [BIOSRequirement("dc/naomi2.zip")], prefersStandalone: false),
        // MAME finds a board's BIOS set (stvbios.zip) beside the games.
        .init(systemID: .model2, cores: [mameCurrent], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .stv, cores: [mameCurrent], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .gaelco, cores: [mameCurrent], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .model3, cores: [RecommendedCore("supermodel_libretro", "Supermodel", String(localized: "The Sega Model 3 emulator.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .psp, cores: [RecommendedCore("ppsspp_libretro", "PPSSPP", String(localized: "The PSP emulator, with upscaling.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .ps2, cores: [RecommendedCore("pcsx2_libretro", "PCSX2", String(localized: "The reference PS2 emulator, as a RetroArch core.", bundle: .module))], standalone: [pcsx2], bios: [BIOSRequirement("pcsx2/bios/", note: "Any PS2 BIOS dump, in this folder", supportedDumps: ["scph39001.bin", "scph70012.bin", "scph77001.bin", "scph30004r.bin", "scph70004.bin", "scph50000.bin", "scph77000.bin"])], prefersStandalone: false),
        .init(systemID: .ps3, cores: [RecommendedCore("rpcs3_libretro", "RPCS3", String(localized: "RPCS3 as a RetroArch core; the standalone app is the reference.", bundle: .module))], standalone: [rpcs3], bios: [], prefersStandalone: true),
        .init(systemID: .ps4, cores: [], standalone: [shadPS4], bios: [], prefersStandalone: true),
        .init(systemID: .psvita, cores: [], standalone: [vita3K], bios: [], prefersStandalone: true),
        .init(systemID: .xbox, cores: [], standalone: [xemu], bios: [], prefersStandalone: true),
        .init(systemID: .scummvm, cores: [RecommendedCore("scummvm_libretro_libretro", "ScummVM", String(localized: "LucasArts, Sierra and other classic adventures.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .doom, cores: [RecommendedCore("prboom_libretro_libretro", "PrBoom", String(localized: "DOOM, DOOM II, Final DOOM and their WADs.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .quake, cores: [RecommendedCore("tyrquake_libretro_libretro", "TyrQuake", String(localized: "Quake and its mission packs.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .easyrpg, cores: [RecommendedCore("easyrpg_libretro_libretro", "EasyRPG Player", String(localized: "Games made with RPG Maker 2000 and 2003.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .x68000, cores: [RecommendedCore("px68k_libretro", "PX68k", String(localized: "The Sharp X68000 home computer.", bundle: .module))], standalone: [], bios: [BIOSRequirement("keropi/iplrom.dat"), BIOSRequirement("keropi/cgrom.dat"), BIOSRequirement("keropi/iplrom30.dat", required: false, note: "X68030 model")], prefersStandalone: false),
        .init(systemID: .pc88, cores: [RecommendedCore("quasi88_libretro", "QUASI88", String(localized: "The NEC PC-8801 home computer.", bundle: .module))], standalone: [], bios: [BIOSRequirement("quasi88/n88.rom"), BIOSRequirement("quasi88/n88_0.rom"), BIOSRequirement("quasi88/n88_1.rom", required: false), BIOSRequirement("quasi88/n88_2.rom", required: false), BIOSRequirement("quasi88/n88_3.rom", required: false), BIOSRequirement("quasi88/n88n.rom", required: false), BIOSRequirement("quasi88/disk.rom", required: false), BIOSRequirement("quasi88/n88knj1.rom", required: false, note: "Kanji font")], prefersStandalone: false),
        .init(systemID: .pc98, cores: [RecommendedCore("np2kai_libretro", "Neko Project II kai", String(localized: "The NEC PC-9801 home computer.", bundle: .module))], standalone: [], bios: [BIOSRequirement("np2kai/bios.rom", required: false, note: "Without it a built-in replacement runs fewer games"), BIOSRequirement("np2kai/font.bmp", required: false, note: "Japanese font (or FONT.ROM)"), BIOSRequirement("np2kai/itf.rom", required: false), BIOSRequirement("np2kai/sound.rom", required: false)], prefersStandalone: false),
        .init(systemID: .pico8, cores: [RecommendedCore("retro8_libretro", "Retro8", String(localized: "Plays PICO-8 carts (.p8 and .p8.png).", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .tic80, cores: [RecommendedCore("tic80_libretro", "TIC-80", String(localized: "The TIC-80 fantasy console.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .wasm4, cores: [RecommendedCore("wasm4_libretro", "WASM-4", String(localized: "The WASM-4 fantasy console.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .arduboy, cores: [RecommendedCore("arduous_libretro", "Arduous", String(localized: "The Arduboy handheld.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .vic20, cores: [RecommendedCore("vice_xvic_libretro", "VICE xvic", String(localized: "The Commodore VIC-20.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .plus4, cores: [RecommendedCore("vice_xplus4_libretro", "VICE xplus4", String(localized: "The Commodore Plus/4 and 16.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .c128, cores: [RecommendedCore("vice_x128_libretro", "VICE x128", String(localized: "The Commodore 128.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .zx81, cores: [RecommendedCore("81_libretro", "EightyOne", String(localized: "The Sinclair ZX81.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .macintosh, cores: [RecommendedCore("minivmac_libretro", "Mini vMac", String(localized: "The classic 68k Macintosh, System 6 and 7.", bundle: .module))], standalone: [], bios: [BIOSRequirement("MacII.ROM")], prefersStandalone: false),
        .init(systemID: .msx, cores: [RecommendedCore("bluemsx_libretro", "blueMSX", String(localized: "Accurate MSX, MSX2 and MSX2+.", bundle: .module)), RecommendedCore("fmsx_libretro", "fMSX", String(localized: "Lighter MSX core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .dos, cores: [RecommendedCore("dosbox_pure_libretro", "DOSBox Pure", String(localized: "Plays zipped DOS games directly.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .wonderswan, cores: [beetleWonderSwan], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .wonderswancolor, cores: [beetleWonderSwan], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .ngp, cores: [beetleNGP, race], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .ngpc, cores: [beetleNGP, race], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .neogeocd, cores: [RecommendedCore("neocd_libretro", "NeoCD", String(localized: "The Neo Geo CD core.", bundle: .module))], standalone: [], bios: [BIOSRequirement("neocd/neocd.bin", note: "Neo Geo CD BIOS (front or top loader)")], prefersStandalone: false),
        .init(systemID: .atarist, cores: [RecommendedCore("hatari_libretro", "Hatari", String(localized: "The Atari ST, STE, TT and Falcon emulator.", bundle: .module))], standalone: [], bios: [BIOSRequirement("tos.img", note: "Atari TOS ROM")], prefersStandalone: false),
        .init(systemID: .atari800, cores: [RecommendedCore("atari800_libretro", "Atari800", String(localized: "Atari 400/800, XL and XE.", bundle: .module))], standalone: [], bios: [BIOSRequirement("ATARIXL.ROM", required: false, note: "Optional; needed by some XL/XE games"), BIOSRequirement("ATARIBAS.ROM", required: false, note: "Optional; Atari BASIC")], prefersStandalone: false),
        .init(systemID: .colecovision, cores: [RecommendedCore("gearcoleco_libretro", "Gearcoleco", String(localized: "Accurate ColecoVision core.", bundle: .module)), RecommendedCore("bluemsx_libretro", "blueMSX", String(localized: "Also runs ColecoVision.", bundle: .module))], standalone: [], bios: [BIOSRequirement("colecovision.rom")], prefersStandalone: false),
        .init(systemID: .intellivision, cores: [RecommendedCore("freeintv_libretro", "FreeIntv", String(localized: "The Intellivision core.", bundle: .module))], standalone: [], bios: [BIOSRequirement("exec.bin", note: "Executive ROM"), BIOSRequirement("grom.bin", note: "Graphics ROM")], prefersStandalone: false),
        .init(systemID: .vectrex, cores: [RecommendedCore("vecx_libretro", "vecx", String(localized: "The Vectrex core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .odyssey2, cores: [RecommendedCore("o2em_libretro", "O2EM", String(localized: "Odyssey² and Videopac.", bundle: .module))], standalone: [], bios: [BIOSRequirement("o2rom.bin")], prefersStandalone: false),
        .init(systemID: .channelf, cores: [RecommendedCore("freechaf_libretro", "FreeChaF", String(localized: "The Channel F core.", bundle: .module))], standalone: [], bios: [BIOSRequirement("sl31253.bin"), BIOSRequirement("sl31254.bin")], prefersStandalone: false),
        .init(systemID: .c64, cores: [RecommendedCore("vice_x64sc_libretro", "VICE x64sc", String(localized: "Accurate Commodore 64.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .amiga, cores: [RecommendedCore("puae_libretro", "PUAE", String(localized: "Amiga 500 to 1200, CD32 and CDTV.", bundle: .module))], standalone: [], bios: [BIOSRequirement("kick34005.A500", required: false, note: "Kickstart 1.3; without it a free replacement runs fewer games")], prefersStandalone: false),
        .init(systemID: .zxspectrum, cores: [RecommendedCore("fuse_libretro", "Fuse", String(localized: "The ZX Spectrum emulator.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .amstradcpc, cores: [RecommendedCore("cap32_libretro", "Caprice32", String(localized: "The Amstrad CPC core.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .mame, cores: [mameCurrent, RecommendedCore("mame2003_plus_libretro", "MAME 2003-Plus", String(localized: "Older, lighter MAME; needs 0.78 romsets.", bundle: .module))], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .fbneo, cores: [fbneo], standalone: [], bios: [], prefersStandalone: false),
        // No libretro core runs Triforce games; Dolphin's own app does.
        .init(systemID: .triforce, cores: [], standalone: [dolphin], bios: [], prefersStandalone: true),

        .init(systemID: .cdi, cores: [
            RecommendedCore("same_cdi_libretro", "SAME CDi", String(localized: "The CD-i core.", bundle: .module))
        ], standalone: [], bios: [
            BIOSRequirement("same_cdi/bios/cdimono1.zip")
        ], prefersStandalone: false)
    ]

    public static func recommendation(for systemID: CanonicalSystemID) -> SystemEmulatorRecommendation? {
        recommendations.first { $0.systemID == systemID.baseSystem }
    }

    /// Every system whose catalog entry lists `coreIdentifier` — used so a
    /// multi-system core (Genesis Plus GX runs Genesis, Master System, Game
    /// Gear and Sega CD) shows up under all of them, not just the one
    /// system its `.info` file names.
    public static func systems(forCore coreIdentifier: String) -> [CanonicalSystemID] {
        recommendations.filter { $0.cores.contains { $0.coreIdentifier == coreIdentifier } }.map(\.systemID)
    }
}
