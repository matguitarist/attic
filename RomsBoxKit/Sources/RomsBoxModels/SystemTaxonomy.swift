/// The library convention a given system folder was scanned from. Recorded
/// per system (not globally) since a single ROMs root can mix conventions.
public enum LibraryFormat: String, Sendable, Codable, CaseIterable {
    case batocera
    case esde
}

/// One MVP system's identity across the three vocabularies that need to be
/// reconciled: Batocera/RetroBat's folder short-name, ES-DE's folder
/// short-name, and RetroArch core `.info` files' `systemid` field.
public struct SystemDefinition: Sendable, Hashable {
    public let canonicalID: CanonicalSystemID
    public let displayName: String
    public let batoceraShortName: String
    public let esdeShortName: String
    /// RetroArch core `.info` `systemid` values known to map to this system.
    /// Confirmed against real installed cores' `.info` files (nestopia,
    /// snes9x, genesis_plus_gx, mednafen_psx/swanstation, mgba) in Phase 5;
    /// the first entry is the confirmed value, later entries are defensive
    /// fallback aliases in case a different installed core disagrees.
    public let retroArchSystemIDs: [String]

    public init(
        canonicalID: CanonicalSystemID,
        displayName: String,
        batoceraShortName: String,
        esdeShortName: String,
        retroArchSystemIDs: [String]
    ) {
        self.canonicalID = canonicalID
        self.displayName = displayName
        self.batoceraShortName = batoceraShortName
        self.esdeShortName = esdeShortName
        self.retroArchSystemIDs = retroArchSystemIDs
    }
}

/// Canonical system table, and lookup functions from each format-specific
/// vocabulary to a `SystemDefinition`.
public enum SystemTaxonomy {
    /// The original 5 MVP systems' `retroArchSystemIDs` were confirmed
    /// against real installed cores' `.info` files (Phase 5). Systems added
    /// afterward use well-known libretro core `systemid` conventions
    /// instead, since there was no matching real install to verify
    /// against — lower-stakes than it sounds, since this field only drives
    /// auto-suggesting a default core in Settings, not folder
    /// detection/scraping, which key off `batoceraShortName`/`esdeShortName`
    /// and `CanonicalSystemID` instead.
    public static let allSystems: [SystemDefinition] = [
        SystemDefinition(
            canonicalID: .nes,
            displayName: "Nintendo Entertainment System",
            batoceraShortName: "nes",
            esdeShortName: "nes",
            retroArchSystemIDs: ["nes"]
        ),
        SystemDefinition(
            canonicalID: .snes,
            displayName: "Super Nintendo Entertainment System",
            batoceraShortName: "snes",
            esdeShortName: "snes",
            retroArchSystemIDs: ["super_nes", "snes"]
        ),
        SystemDefinition(
            canonicalID: .genesis,
            displayName: "Sega Genesis / Mega Drive",
            batoceraShortName: "megadrive",
            esdeShortName: "genesis",
            retroArchSystemIDs: ["mega_drive", "megadrive", "genesis"]
        ),
        SystemDefinition(
            canonicalID: .psx,
            displayName: "Sony PlayStation",
            batoceraShortName: "psx",
            esdeShortName: "psx",
            retroArchSystemIDs: ["playstation", "psx"]
        ),
        SystemDefinition(
            canonicalID: .gba,
            displayName: "Game Boy Advance",
            batoceraShortName: "gba",
            esdeShortName: "gba",
            retroArchSystemIDs: ["game_boy_advance", "gba"]
        ),
        SystemDefinition(
            canonicalID: .mastersystem,
            displayName: "Sega Master System",
            batoceraShortName: "mastersystem",
            esdeShortName: "mastersystem",
            retroArchSystemIDs: ["master_system", "sega_master_system"]
        ),
        SystemDefinition(
            canonicalID: .gamegear,
            displayName: "Sega Game Gear",
            batoceraShortName: "gamegear",
            esdeShortName: "gamegear",
            retroArchSystemIDs: ["game_gear", "sega_game_gear"]
        ),
        SystemDefinition(
            canonicalID: .segacd,
            displayName: "Sega CD",
            batoceraShortName: "megacd",
            esdeShortName: "segacd",
            retroArchSystemIDs: ["sega_cd", "mega_cd", "megacd"]
        ),
        SystemDefinition(
            canonicalID: .saturn,
            displayName: "Sega Saturn",
            batoceraShortName: "saturn",
            esdeShortName: "saturn",
            retroArchSystemIDs: ["saturn", "sega_saturn"]
        ),
        SystemDefinition(
            canonicalID: .dreamcast,
            displayName: "Sega Dreamcast",
            batoceraShortName: "dreamcast",
            esdeShortName: "dreamcast",
            retroArchSystemIDs: ["dreamcast", "sega_dreamcast"]
        ),
        SystemDefinition(
            canonicalID: .sega32x,
            displayName: "Sega 32X",
            batoceraShortName: "sega32x",
            esdeShortName: "sega32x",
            retroArchSystemIDs: ["sega_32x", "32x"]
        ),
        SystemDefinition(
            canonicalID: .atari2600,
            displayName: "Atari 2600",
            batoceraShortName: "atari2600",
            esdeShortName: "atari2600",
            retroArchSystemIDs: ["atari_2600", "atari2600"]
        ),
        SystemDefinition(
            canonicalID: .atari5200,
            displayName: "Atari 5200",
            batoceraShortName: "atari5200",
            esdeShortName: "atari5200",
            retroArchSystemIDs: ["atari_5200", "atari5200"]
        ),
        SystemDefinition(
            canonicalID: .atari7800,
            displayName: "Atari 7800",
            batoceraShortName: "atari7800",
            esdeShortName: "atari7800",
            retroArchSystemIDs: ["atari_7800", "atari7800"]
        ),
        SystemDefinition(
            canonicalID: .atarilynx,
            displayName: "Atari Lynx",
            batoceraShortName: "lynx",
            esdeShortName: "atarilynx",
            retroArchSystemIDs: ["atari_lynx", "lynx"]
        ),
        SystemDefinition(
            canonicalID: .atarijaguar,
            displayName: "Atari Jaguar",
            batoceraShortName: "jaguar",
            esdeShortName: "atarijaguar",
            retroArchSystemIDs: ["atari_jaguar", "jaguar"]
        ),
        SystemDefinition(
            canonicalID: .pcengine,
            displayName: "NEC TurboGrafx-16",
            batoceraShortName: "pcengine",
            // Confirmed directly against a real ES-DE library ("tg16" — not
            // "turbografx16", which some ES-DE forks/docs use instead).
            esdeShortName: "tg16",
            retroArchSystemIDs: ["pc_engine", "turbografx_16", "pce"]
        ),
        SystemDefinition(
            canonicalID: .pcenginecd,
            displayName: "NEC TurboGrafx-CD",
            batoceraShortName: "pcenginecd",
            esdeShortName: "turbografxcd",
            retroArchSystemIDs: ["pc_engine_cd", "turbografx_16_cd", "pce_cd"]
        ),
        SystemDefinition(
            canonicalID: .pcfx,
            displayName: "NEC PC-FX",
            batoceraShortName: "pcfx",
            esdeShortName: "pcfx",
            retroArchSystemIDs: ["pc_fx", "pcfx"]
        ),
        SystemDefinition(
            canonicalID: .supergrafx,
            displayName: "NEC SuperGrafx",
            batoceraShortName: "supergrafx",
            esdeShortName: "supergrafx",
            retroArchSystemIDs: ["pc_engine_supergrafx", "supergrafx", "sgx"]
        ),
        SystemDefinition(
            canonicalID: .threedo,
            displayName: "3DO",
            batoceraShortName: "3do",
            esdeShortName: "3do",
            retroArchSystemIDs: ["3do", "panasonic_3do"]
        ),
        SystemDefinition(
            canonicalID: .cdi,
            displayName: "Philips CD-i",
            batoceraShortName: "cdi",
            esdeShortName: "cdimono1",
            retroArchSystemIDs: ["cd_i", "cdi", "philips_cd_i"]
        )
    ]

    private static let byBatoceraShortName: [String: SystemDefinition] =
        Dictionary(uniqueKeysWithValues: allSystems.map { ($0.batoceraShortName, $0) })

    private static let byESDEShortName: [String: SystemDefinition] =
        Dictionary(uniqueKeysWithValues: allSystems.map { ($0.esdeShortName, $0) })

    private static let byCanonicalID: [CanonicalSystemID: SystemDefinition] =
        Dictionary(uniqueKeysWithValues: allSystems.map { ($0.canonicalID, $0) })

    private static let byRetroArchSystemID: [String: SystemDefinition] = {
        var map: [String: SystemDefinition] = [:]
        for definition in allSystems {
            for id in definition.retroArchSystemIDs {
                map[id] = definition
            }
        }
        return map
    }()

    public static func system(forBatoceraShortName name: String) -> SystemDefinition? {
        byBatoceraShortName[name]
    }

    public static func system(forESDEShortName name: String) -> SystemDefinition? {
        byESDEShortName[name]
    }

    public static func system(forRetroArchSystemID id: String) -> SystemDefinition? {
        byRetroArchSystemID[id]
    }

    public static func definition(for id: CanonicalSystemID) -> SystemDefinition? {
        byCanonicalID[id]
    }

    /// Looks up a system folder short-name against both conventions' short-name
    /// tables, since the format hasn't necessarily been detected yet at the
    /// point a folder is first encountered.
    public static func system(forShortName name: String) -> SystemDefinition? {
        byBatoceraShortName[name] ?? byESDEShortName[name]
    }
}
