import Foundation
import RomsBoxModels

/// A RetroArch core RomsBox knows how to install, from libretro's official
/// buildbot — the same source RetroArch's own Online Updater downloads
/// from. Nothing is bundled with RomsBox itself.
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
    }

    public let id: String
    public let name: String
    public let summary: String
    /// The `.app` bundle name inside the archive and once installed.
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

        public init(_ section: String, _ key: String, _ value: String) {
            self.section = section
            self.key = key
            self.value = value
        }
    }

    /// The settings file, relative to the redirected HOME.
    public let settingsRelativePath: String
    public let settings: [Setting]
}

/// A BIOS/firmware file a system needs. These are copyrighted and must be
/// dumped from hardware the user owns, so RomsBox only *checks* for them
/// and says where they go — it never downloads them.
public struct BIOSRequirement: Sendable, Hashable {
    public let fileName: String
    public let required: Bool
    public let note: String?

    public init(_ fileName: String, required: Bool = true, note: String? = nil) {
        self.fileName = fileName
        self.required = required
        self.note = note
    }
}

/// Everything RomsBox recommends for running one system.
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
}

/// The curated table behind RomsBox's emulator setup. Choices favor
/// accuracy where Apple Silicon handles it comfortably, and every core here
/// was confirmed present on the arm64 macOS buildbot.
public enum EmulatorCatalog {
    public static let buildbotCoresURL = URL(string: "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/")!
    /// Every core's `.info` file in one archive — RomsBox needs these to
    /// know which system a core runs and which file extensions it takes.
    public static let coreInfoArchiveURL = URL(string: "https://buildbot.libretro.com/assets/frontend/info.zip")!
    public static let retroArchStableIndexURL = URL(string: "https://buildbot.libretro.com/stable/")!
    public static let retroArchHomepageURL = URL(string: "https://www.retroarch.com")!

    /// CRC32 per core, the same file RetroArch's Online Updater reads to
    /// decide whether a core is current.
    public static let buildbotCoreChecksumsURL = buildbotCoresURL.appending(path: ".index-extended")

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
        summary: "The most accurate and polished PlayStation emulator, with upscaling and per-game fixes.",
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
            ]
        )
    )

    // Dreamcast deliberately has no standalone entry: the Flycast core is
    // the same emulator, and as a core its config, saves and states live in
    // the Emulation folder like every other RetroArch system — the
    // standalone app keeps its settings in ~/Library.
    public static let standaloneEmulators: [StandaloneEmulator] = [duckStation]

    // MARK: - Per-system table

    private static let genesisPlusGX = RecommendedCore("genesis_plus_gx_libretro", "Genesis Plus GX", "Highly accurate Sega 8/16-bit and Sega CD.")
    private static let picoDrive = RecommendedCore("picodrive_libretro", "PicoDrive", "Fast; the only option with 32X support.")
    private static let beetlePCE = RecommendedCore("mednafen_pce_libretro", "Beetle PCE", "Accurate PC Engine, CD and SuperGrafx.")
    private static let beetlePCEFast = RecommendedCore("mednafen_pce_fast_libretro", "Beetle PCE Fast", "Lighter PC Engine core.")

    public static let recommendations: [SystemEmulatorRecommendation] = [
        .init(systemID: .nes, cores: [
            RecommendedCore("mesen_libretro", "Mesen", "Most accurate NES core."),
            RecommendedCore("nestopia_libretro", "Nestopia UE", "Accurate and lighter."),
            RecommendedCore("fceumm_libretro", "FCEUmm", "Fast, broad mapper support.")
        ], standalone: [], bios: [], prefersStandalone: false),

        .init(systemID: .snes, cores: [
            RecommendedCore("snes9x_libretro", "Snes9x", "Accurate and fast — the usual choice."),
            RecommendedCore("bsnes_libretro", "bsnes", "Cycle-accurate; heavier.")
        ], standalone: [], bios: [], prefersStandalone: false),

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
            RecommendedCore("swanstation_libretro", "SwanStation", "DuckStation's engine as a RetroArch core."),
            RecommendedCore("mednafen_psx_hw_libretro", "Beetle PSX HW", "Very accurate, with upscaling."),
            RecommendedCore("pcsx_rearmed_libretro", "PCSX ReARMed", "Fast; can run without a BIOS.")
        ], standalone: [duckStation], bios: [
            BIOSRequirement("scph5501.bin", note: "US"),
            BIOSRequirement("scph5502.bin", required: false, note: "Europe"),
            BIOSRequirement("scph5500.bin", required: false, note: "Japan")
        ], prefersStandalone: true),

        .init(systemID: .gba, cores: [
            RecommendedCore("mgba_libretro", "mGBA", "Accurate and fast — the standard GBA core.")
        ], standalone: [], bios: [
            BIOSRequirement("gba_bios.bin", required: false, note: "Optional; improves accuracy")
        ], prefersStandalone: false),

        .init(systemID: .saturn, cores: [
            RecommendedCore("mednafen_saturn_libretro", "Beetle Saturn", "Most accurate Saturn core."),
            RecommendedCore("yabasanshiro_libretro", "YabaSanshiro", "Faster, less accurate.")
        ], standalone: [], bios: [
            BIOSRequirement("sega_101.bin", note: "Japan"),
            BIOSRequirement("mpr-17933.bin", note: "US/Europe")
        ], prefersStandalone: false),

        .init(systemID: .dreamcast, cores: [
            RecommendedCore("flycast_libretro", "Flycast", "The Dreamcast core.")
        ], standalone: [], bios: [
            BIOSRequirement("dc/dc_boot.bin", required: false, note: "Optional; Flycast can boot most games without it")
        ], prefersStandalone: false),

        .init(systemID: .atari2600, cores: [
            RecommendedCore("stella_libretro", "Stella", "The reference Atari 2600 emulator.")
        ], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .atari5200, cores: [
            RecommendedCore("a5200_libretro", "a5200", "Dedicated 5200 core."),
            RecommendedCore("atari800_libretro", "Atari800", "Atari 8-bit family including 5200.")
        ], standalone: [], bios: [BIOSRequirement("5200.rom")], prefersStandalone: false),
        .init(systemID: .atari7800, cores: [
            RecommendedCore("prosystem_libretro", "ProSystem", "The Atari 7800 core.")
        ], standalone: [], bios: [
            BIOSRequirement("7800 BIOS (U).rom", required: false, note: "Optional")
        ], prefersStandalone: false),
        .init(systemID: .atarilynx, cores: [
            RecommendedCore("handy_libretro", "Handy", "The reference Lynx emulator."),
            RecommendedCore("mednafen_lynx_libretro", "Beetle Lynx", "Mednafen's Lynx core.")
        ], standalone: [], bios: [BIOSRequirement("lynxboot.img")], prefersStandalone: false),
        .init(systemID: .atarijaguar, cores: [
            RecommendedCore("virtualjaguar_libretro", "Virtual Jaguar", "The only Jaguar core.")
        ], standalone: [], bios: [], prefersStandalone: false),

        .init(systemID: .pcengine, cores: [beetlePCE, beetlePCEFast], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .pcenginecd, cores: [beetlePCE, beetlePCEFast], standalone: [], bios: [
            BIOSRequirement("syscard3.pce", note: "System Card 3.0")
        ], prefersStandalone: false),
        .init(systemID: .supergrafx, cores: [
            RecommendedCore("mednafen_supergrafx_libretro", "Beetle SuperGrafx", "Dedicated SuperGrafx core."),
            beetlePCE
        ], standalone: [], bios: [], prefersStandalone: false),
        .init(systemID: .pcfx, cores: [
            RecommendedCore("mednafen_pcfx_libretro", "Beetle PC-FX", "The only PC-FX core.")
        ], standalone: [], bios: [BIOSRequirement("pcfx.rom")], prefersStandalone: false),

        .init(systemID: .threedo, cores: [
            RecommendedCore("opera_libretro", "Opera", "The 3DO core.")
        ], standalone: [], bios: [
            BIOSRequirement("panafz10.bin", note: "Panasonic FZ-10; other 3DO BIOS revisions also work")
        ], prefersStandalone: false),
        .init(systemID: .cdi, cores: [
            RecommendedCore("same_cdi_libretro", "SAME CDi", "The CD-i core.")
        ], standalone: [], bios: [
            BIOSRequirement("same_cdi/bios/cdimono1.zip")
        ], prefersStandalone: false)
    ]

    public static func recommendation(for systemID: CanonicalSystemID) -> SystemEmulatorRecommendation? {
        recommendations.first { $0.systemID == systemID }
    }

    /// Every system whose catalog entry lists `coreIdentifier` — used so a
    /// multi-system core (Genesis Plus GX runs Genesis, Master System, Game
    /// Gear and Sega CD) shows up under all of them, not just the one
    /// system its `.info` file names.
    public static func systems(forCore coreIdentifier: String) -> [CanonicalSystemID] {
        recommendations.filter { $0.cores.contains { $0.coreIdentifier == coreIdentifier } }.map(\.systemID)
    }
}
