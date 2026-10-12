/// The library convention a given system folder was scanned from. Recorded
/// per system (not globally) since a single ROMs root can mix conventions.
public enum LibraryFormat: String, Sendable, Codable, CaseIterable {
    case batocera
    case esde
}

/// What kind of machine a system is — groups the sidebar and Cabinet Mode.
/// Declaration order is display order.
public enum SystemCategory: String, Sendable, Hashable, CaseIterable {
    case console
    case handheld
    case arcade
    case computer
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
    public let category: SystemCategory
    /// More ROM folder names that mean this system (e.g. msx2, amiga1200,
    /// videopac), as Batocera, RetroBat and ES-DE variously name them.
    public let otherShortNames: [String]

    public init(
        canonicalID: CanonicalSystemID,
        displayName: String,
        batoceraShortName: String,
        esdeShortName: String,
        retroArchSystemIDs: [String],
        category: SystemCategory = .console,
        otherShortNames: [String] = []
    ) {
        self.canonicalID = canonicalID
        self.displayName = displayName
        self.batoceraShortName = batoceraShortName
        self.esdeShortName = esdeShortName
        self.retroArchSystemIDs = retroArchSystemIDs
        self.category = category
        self.otherShortNames = otherShortNames
    }

    /// Every ROM folder name recognized for this system, most common first.
    public var allShortNames: [String] {
        ([batoceraShortName, esdeShortName] + otherShortNames)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
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
            retroArchSystemIDs: ["game_boy_advance", "gba"],
            category: .handheld
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
            retroArchSystemIDs: ["game_gear", "sega_game_gear"],
            category: .handheld
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
            retroArchSystemIDs: ["atari_lynx", "lynx"],
            category: .handheld
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
        ),
        SystemDefinition(
            canonicalID: .virtualboy,
            displayName: "Nintendo Virtual Boy",
            batoceraShortName: "virtualboy",
            esdeShortName: "virtualboy",
            retroArchSystemIDs: ["virtual_boy", "virtualboy"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .neogeo,
            displayName: "SNK Neo Geo",
            batoceraShortName: "neogeo",
            esdeShortName: "neogeo",
            retroArchSystemIDs: ["neogeo", "neo_geo"],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .cps1,
            displayName: "Capcom CPS-1",
            batoceraShortName: "cps1",
            esdeShortName: "cps1",
            retroArchSystemIDs: [],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .cps2,
            displayName: "Capcom CPS-2",
            batoceraShortName: "cps2",
            esdeShortName: "cps2",
            retroArchSystemIDs: [],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .cps3,
            displayName: "Capcom CPS-3",
            batoceraShortName: "cps3",
            esdeShortName: "cps3",
            retroArchSystemIDs: [],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .triforce,
            displayName: "Triforce",
            batoceraShortName: "triforce",
            esdeShortName: "triforce",
            retroArchSystemIDs: [],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .gb,
            displayName: "Nintendo Game Boy",
            batoceraShortName: "gb",
            esdeShortName: "gb",
            retroArchSystemIDs: ["game_boy", "gb"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .gbc,
            displayName: "Nintendo Game Boy Color",
            batoceraShortName: "gbc",
            esdeShortName: "gbc",
            retroArchSystemIDs: ["game_boy_color", "gbc"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .n64,
            displayName: "Nintendo 64",
            batoceraShortName: "n64",
            esdeShortName: "n64",
            retroArchSystemIDs: ["nintendo_64", "n64"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .nds,
            displayName: "Nintendo DS",
            batoceraShortName: "nds",
            esdeShortName: "nds",
            retroArchSystemIDs: ["nds", "nintendo_ds"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .n3ds,
            displayName: "Nintendo 3DS",
            batoceraShortName: "3ds",
            esdeShortName: "n3ds",
            retroArchSystemIDs: ["3ds", "nintendo_3ds"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .gamecube,
            displayName: "Nintendo GameCube",
            batoceraShortName: "gamecube",
            esdeShortName: "gc",
            retroArchSystemIDs: ["gamecube"],
            category: .console, otherShortNames: ["ngc"]
        ),
        SystemDefinition(
            canonicalID: .wii,
            displayName: "Nintendo Wii",
            batoceraShortName: "wii",
            esdeShortName: "wii",
            retroArchSystemIDs: ["wii"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .wiiu,
            displayName: "Nintendo Wii U",
            batoceraShortName: "wiiu",
            esdeShortName: "wiiu",
            retroArchSystemIDs: ["wiiu"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .fds,
            displayName: "Famicom Disk System",
            batoceraShortName: "fds",
            esdeShortName: "fds",
            retroArchSystemIDs: [],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .pokemini,
            displayName: "Pokémon Mini",
            batoceraShortName: "pokemini",
            esdeShortName: "pokemini",
            retroArchSystemIDs: ["pokemon_mini"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .gameandwatch,
            displayName: "Game & Watch",
            batoceraShortName: "gameandwatch",
            esdeShortName: "gameandwatch",
            retroArchSystemIDs: ["handheld_electronic", "game_and_watch"],
            category: .handheld, otherShortNames: ["gw"]
        ),
        SystemDefinition(
            canonicalID: .sg1000,
            displayName: "Sega SG-1000",
            batoceraShortName: "sg1000",
            esdeShortName: "sg-1000",
            retroArchSystemIDs: ["sg_1000", "sg1000"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .naomi,
            displayName: "Sega NAOMI",
            batoceraShortName: "naomi",
            esdeShortName: "naomi",
            retroArchSystemIDs: ["naomi"],
            category: .arcade, otherShortNames: ["naomi2", "naomigd"]
        ),
        SystemDefinition(
            canonicalID: .atomiswave,
            displayName: "Sammy Atomiswave",
            batoceraShortName: "atomiswave",
            esdeShortName: "atomiswave",
            retroArchSystemIDs: ["atomiswave"],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .model3,
            displayName: "Sega Model 3",
            batoceraShortName: "model3",
            esdeShortName: "model3",
            retroArchSystemIDs: ["model3"],
            category: .arcade
        ),
        SystemDefinition(
            canonicalID: .psp,
            displayName: "Sony PlayStation Portable",
            batoceraShortName: "psp",
            esdeShortName: "psp",
            retroArchSystemIDs: ["playstation_portable", "psp"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .ps2,
            displayName: "Sony PlayStation 2",
            batoceraShortName: "ps2",
            esdeShortName: "ps2",
            retroArchSystemIDs: ["playstation2", "ps2"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .ps3,
            displayName: "Sony PlayStation 3",
            batoceraShortName: "ps3",
            esdeShortName: "ps3",
            retroArchSystemIDs: ["playstation3", "ps3"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .xbox,
            displayName: "Microsoft Xbox",
            batoceraShortName: "xbox",
            esdeShortName: "xbox",
            retroArchSystemIDs: [],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .msx,
            displayName: "MSX",
            batoceraShortName: "msx1",
            esdeShortName: "msx",
            retroArchSystemIDs: ["msx"],
            category: .computer, otherShortNames: ["msx2", "msx2+", "msxturbor"]
        ),
        SystemDefinition(
            canonicalID: .dos,
            displayName: "MS-DOS",
            batoceraShortName: "dos",
            esdeShortName: "dos",
            retroArchSystemIDs: ["dos"],
            category: .computer
        ),
        SystemDefinition(
            canonicalID: .wonderswan,
            displayName: "Bandai WonderSwan",
            batoceraShortName: "wswan",
            esdeShortName: "wonderswan",
            retroArchSystemIDs: ["wonderswan"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .wonderswancolor,
            displayName: "Bandai WonderSwan Color",
            batoceraShortName: "wswanc",
            esdeShortName: "wonderswancolor",
            retroArchSystemIDs: ["wonderswan_color"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .ngp,
            displayName: "SNK Neo Geo Pocket",
            batoceraShortName: "ngp",
            esdeShortName: "ngp",
            retroArchSystemIDs: ["neo_geo_pocket"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .ngpc,
            displayName: "SNK Neo Geo Pocket Color",
            batoceraShortName: "ngpc",
            esdeShortName: "ngpc",
            retroArchSystemIDs: ["neo_geo_pocket_color"],
            category: .handheld
        ),
        SystemDefinition(
            canonicalID: .neogeocd,
            displayName: "SNK Neo Geo CD",
            batoceraShortName: "neogeocd",
            esdeShortName: "neogeocd",
            retroArchSystemIDs: ["neo_geo_cd"],
            category: .console, otherShortNames: ["neogeocdjp"]
        ),
        SystemDefinition(
            canonicalID: .atarist,
            displayName: "Atari ST",
            batoceraShortName: "atarist",
            esdeShortName: "atarist",
            retroArchSystemIDs: ["atari_st"],
            category: .computer
        ),
        SystemDefinition(
            canonicalID: .atari800,
            displayName: "Atari 8-bit",
            batoceraShortName: "atari800",
            esdeShortName: "atari800",
            retroArchSystemIDs: ["atari_8bit", "atari800"],
            category: .computer, otherShortNames: ["atarixe"]
        ),
        SystemDefinition(
            canonicalID: .colecovision,
            displayName: "ColecoVision",
            batoceraShortName: "colecovision",
            esdeShortName: "colecovision",
            retroArchSystemIDs: ["colecovision"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .intellivision,
            displayName: "Mattel Intellivision",
            batoceraShortName: "intellivision",
            esdeShortName: "intellivision",
            retroArchSystemIDs: ["intellivision"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .vectrex,
            displayName: "Vectrex",
            batoceraShortName: "vectrex",
            esdeShortName: "vectrex",
            retroArchSystemIDs: ["vectrex"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .odyssey2,
            displayName: "Magnavox Odyssey²",
            batoceraShortName: "o2em",
            esdeShortName: "odyssey2",
            retroArchSystemIDs: ["odyssey2"],
            category: .console, otherShortNames: ["videopac"]
        ),
        SystemDefinition(
            canonicalID: .channelf,
            displayName: "Fairchild Channel F",
            batoceraShortName: "channelf",
            esdeShortName: "channelf",
            retroArchSystemIDs: ["channel_f"],
            category: .console
        ),
        SystemDefinition(
            canonicalID: .c64,
            displayName: "Commodore 64",
            batoceraShortName: "c64",
            esdeShortName: "c64",
            retroArchSystemIDs: ["commodore_c64", "c64"],
            category: .computer
        ),
        SystemDefinition(
            canonicalID: .amiga,
            displayName: "Commodore Amiga",
            batoceraShortName: "amiga500",
            esdeShortName: "amiga",
            retroArchSystemIDs: ["commodore_amiga", "amiga"],
            category: .computer, otherShortNames: ["amiga600", "amiga1200"]
        ),
        SystemDefinition(
            canonicalID: .zxspectrum,
            displayName: "ZX Spectrum",
            batoceraShortName: "zxspectrum",
            esdeShortName: "zxspectrum",
            retroArchSystemIDs: ["zx_spectrum"],
            category: .computer
        ),
        SystemDefinition(
            canonicalID: .amstradcpc,
            displayName: "Amstrad CPC",
            batoceraShortName: "amstradcpc",
            esdeShortName: "amstradcpc",
            retroArchSystemIDs: ["cpc", "amstrad_cpc"],
            category: .computer
        ),
        SystemDefinition(
            canonicalID: .mame,
            displayName: "MAME",
            batoceraShortName: "mame",
            esdeShortName: "mame",
            retroArchSystemIDs: ["mame"],
            category: .arcade, otherShortNames: ["arcade"]
        ),
        SystemDefinition(
            canonicalID: .fbneo,
            displayName: "FinalBurn Neo",
            batoceraShortName: "fbneo",
            esdeShortName: "fbneo",
            retroArchSystemIDs: ["fb_alpha", "fbneo"],
            category: .arcade, otherShortNames: ["fba"]
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
    private static let byOtherShortName: [String: SystemDefinition] = {
        var map: [String: SystemDefinition] = [:]
        for definition in allSystems {
            for name in definition.otherShortNames { map[name] = definition }
        }
        return map
    }()

    public static func system(forShortName name: String) -> SystemDefinition? {
        byBatoceraShortName[name] ?? byESDEShortName[name] ?? byOtherShortName[name]
    }
}
