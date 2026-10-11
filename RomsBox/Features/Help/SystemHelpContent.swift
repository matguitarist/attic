import Foundation
import RomsBoxModels

/// The hand-written part of each system's help page. Everything else on the
/// page (ROM folder, file types, emulators, BIOS) comes from the system
/// taxonomy, the emulator catalog and the core info files, so it can't
/// drift from what RomsBox actually does.
struct SystemHelpInfo {
    let manufacturer: String
    let year: Int
    /// English Wikipedia article title.
    let wikipediaTitle: String
    var controls: [String] = []
    var notes: [String] = []

    var wikipediaURL: URL {
        URL(string: "https://en.wikipedia.org/wiki/")!.appending(path: wikipediaTitle)
    }
}

enum SystemHelpContent {
    static func info(for system: CanonicalSystemID) -> SystemHelpInfo? {
        byID[system]
    }

    private static let discNote = String(localized: "Disc images work best as .chd — one compressed file per disc. For .cue/.bin dumps, keep each .cue next to its .bin files.")
    private static let multiDiscNote = String(localized: "For multi-disc games, list the discs in an .m3u playlist (one file name per line) and keep only the .m3u visible, so the emulator can swap discs.")
    private static let romsetNote = String(localized: "Keep each game zipped and named after its romset (for example mslug.zip). Don't unzip or rename them: arcade emulators find games by these names.")
    private static let fbneoVersionNote = String(localized: "Romsets must match FinalBurn Neo's version (1.0.0.03). Sets from other versions or from another emulator may fail to load.")
    private static let coinControls = String(localized: "Select inserts a coin, Start starts the game.")
    private static let sixButtonControls = String(localized: "Six-button fighting games use the four face buttons for light and medium attacks, and L and R for the strongest ones.")

    private static let byID: [CanonicalSystemID: SystemHelpInfo] = [
        .nes: .init(manufacturer: "Nintendo", year: 1983, wikipediaTitle: "Nintendo_Entertainment_System"),
        .snes: .init(manufacturer: "Nintendo", year: 1990, wikipediaTitle: "Super_Nintendo_Entertainment_System"),
        .gba: .init(manufacturer: "Nintendo", year: 2001, wikipediaTitle: "Game_Boy_Advance"),
        .virtualboy: .init(manufacturer: "Nintendo", year: 1995, wikipediaTitle: "Virtual_Boy",
                           controls: [String(localized: "The Virtual Boy's second D-pad is on the right stick.")],
                           notes: [String(localized: "Games show in red and black on a flat screen. RomsBox turns off the core's VR mode, which needs a kind of OpenGL macOS doesn't offer.")]),
        .genesis: .init(manufacturer: "Sega", year: 1988, wikipediaTitle: "Sega_Genesis",
                        controls: [String(localized: "Six-button games use the four face buttons plus L and R.")]),
        .mastersystem: .init(manufacturer: "Sega", year: 1985, wikipediaTitle: "Master_System"),
        .gamegear: .init(manufacturer: "Sega", year: 1990, wikipediaTitle: "Game_Gear"),
        .segacd: .init(manufacturer: "Sega", year: 1991, wikipediaTitle: "Sega_CD", notes: [discNote, multiDiscNote]),
        .sega32x: .init(manufacturer: "Sega", year: 1994, wikipediaTitle: "32X"),
        .saturn: .init(manufacturer: "Sega", year: 1994, wikipediaTitle: "Sega_Saturn", notes: [discNote, multiDiscNote]),
        .dreamcast: .init(manufacturer: "Sega", year: 1998, wikipediaTitle: "Dreamcast",
                          notes: [String(localized: "Dreamcast games work best as .chd or .gdi dumps. The BIOS files go in a dc folder inside the BIOS folder.")]),
        .psx: .init(manufacturer: "Sony", year: 1994, wikipediaTitle: "PlayStation_(console)", notes: [discNote, multiDiscNote]),
        .atari2600: .init(manufacturer: "Atari", year: 1977, wikipediaTitle: "Atari_2600"),
        .atari5200: .init(manufacturer: "Atari", year: 1982, wikipediaTitle: "Atari_5200"),
        .atari7800: .init(manufacturer: "Atari", year: 1986, wikipediaTitle: "Atari_7800"),
        .atarilynx: .init(manufacturer: "Atari", year: 1989, wikipediaTitle: "Atari_Lynx"),
        .atarijaguar: .init(manufacturer: "Atari", year: 1993, wikipediaTitle: "Atari_Jaguar",
                            controls: [String(localized: "The Jaguar's number pad isn't on modern controllers; games that need it map its keys to spare buttons.")]),
        .pcengine: .init(manufacturer: "NEC", year: 1987, wikipediaTitle: "TurboGrafx-16"),
        .pcenginecd: .init(manufacturer: "NEC", year: 1988, wikipediaTitle: "TurboGrafx-CD", notes: [discNote]),
        .supergrafx: .init(manufacturer: "NEC", year: 1989, wikipediaTitle: "PC_Engine_SuperGrafx"),
        .pcfx: .init(manufacturer: "NEC", year: 1994, wikipediaTitle: "PC-FX", notes: [discNote]),
        .threedo: .init(manufacturer: "The 3DO Company", year: 1993, wikipediaTitle: "3DO_Interactive_Multiplayer", notes: [discNote]),
        .cdi: .init(manufacturer: "Philips", year: 1991, wikipediaTitle: "CD-i", notes: [discNote]),
        .neogeo: .init(manufacturer: "SNK", year: 1990, wikipediaTitle: "Neo_Geo_(system)",
                       controls: [String(localized: "Neo Geo A, B, C and D are the bottom, right, left and top buttons."), coinControls],
                       notes: [romsetNote, fbneoVersionNote,
                               String(localized: "neogeo.zip (the Neo Geo BIOS set) goes in the BIOS folder, still zipped."),
                               String(localized: "Free play is on by default (Settings › General › Arcade), so Start begins a game without coins. Games first show the Neo Geo boot screen for about 10 seconds.")]),
        .cps1: .init(manufacturer: "Capcom", year: 1988, wikipediaTitle: "CP_System",
                     controls: [coinControls, sixButtonControls], notes: [romsetNote, fbneoVersionNote]),
        .cps2: .init(manufacturer: "Capcom", year: 1993, wikipediaTitle: "CP_System_II",
                     controls: [coinControls, sixButtonControls], notes: [romsetNote, fbneoVersionNote]),
        .cps3: .init(manufacturer: "Capcom", year: 1996, wikipediaTitle: "CP_System_III",
                     controls: [coinControls, sixButtonControls], notes: [romsetNote, fbneoVersionNote]),
        .gb: .init(manufacturer: "Nintendo", year: 1989, wikipediaTitle: "Game_Boy"),
        .gbc: .init(manufacturer: "Nintendo", year: 1998, wikipediaTitle: "Game_Boy_Color"),
        .n64: .init(manufacturer: "Nintendo", year: 1996, wikipediaTitle: "Nintendo_64"),
        .nds: .init(manufacturer: "Nintendo", year: 2004, wikipediaTitle: "Nintendo_DS",
                    controls: [String(localized: "The touch screen follows the mouse; click to touch.")]),
        .n3ds: .init(manufacturer: "Nintendo", year: 2011, wikipediaTitle: "Nintendo_3DS",
                    controls: [String(localized: "The touch screen follows the mouse; click to touch.")],
                    notes: [String(localized: "Use decrypted game dumps (.3ds, .cci or .cxi).")]),
        .gamecube: .init(manufacturer: "Nintendo", year: 2001, wikipediaTitle: "GameCube",
                    controls: [String(localized: "Dolphin uses its own controller setup. Configure it once in Dolphin (Controllers) — RomsBox's controller settings don't apply to the Dolphin app.")],
                    notes: [String(localized: "Dumps work best as .rvz (compressed, lossless) or .iso.")]),
        .wii: .init(manufacturer: "Nintendo", year: 2006, wikipediaTitle: "Wii",
                    controls: [String(localized: "Dolphin uses its own controller setup. Configure it once in Dolphin (Controllers) — RomsBox's controller settings don't apply to the Dolphin app.")],
                    notes: [String(localized: "Dumps work best as .rvz (compressed, lossless), .wbfs or .iso.")]),
        .wiiu: .init(manufacturer: "Nintendo", year: 2012, wikipediaTitle: "Wii_U",
                    notes: [String(localized: "Use .wua files (Cemu's compressed format), or .wud/.wux disc images.")]),
        .fds: .init(manufacturer: "Nintendo", year: 1986, wikipediaTitle: "Family_Computer_Disk_System",
                    controls: [String(localized: "Select switches the disk side in most games.")]),
        .pokemini: .init(manufacturer: "Nintendo", year: 2001, wikipediaTitle: "Pokémon_Mini"),
        .gameandwatch: .init(manufacturer: "Nintendo", year: 1980, wikipediaTitle: "Game_&_Watch",
                    notes: [String(localized: "Game & Watch games are .mgw files, converted from MAME's artwork and romsets.")]),
        .sg1000: .init(manufacturer: "Sega", year: 1983, wikipediaTitle: "SG-1000"),
        .naomi: .init(manufacturer: "Sega", year: 1998, wikipediaTitle: "Sega_NAOMI",
                    controls: [String(localized: "Select inserts a coin, Start starts the game.")],
                    notes: [String(localized: "Keep each game zipped with its MAME romset name. The NAOMI BIOS (naomi.zip) goes in a dc folder inside the BIOS folder.")]),
        .atomiswave: .init(manufacturer: "Sammy", year: 2003, wikipediaTitle: "Atomiswave",
                    controls: [String(localized: "Select inserts a coin, Start starts the game.")],
                    notes: [String(localized: "Keep each game zipped with its MAME romset name. The Atomiswave BIOS (awbios.zip) goes in a dc folder inside the BIOS folder.")]),
        .model3: .init(manufacturer: "Sega", year: 1996, wikipediaTitle: "Sega_Model_3",
                    controls: [String(localized: "Select inserts a coin, Start starts the game.")],
                    notes: [String(localized: "Keep each game zipped with its MAME romset name.")]),
        .psp: .init(manufacturer: "Sony", year: 2004, wikipediaTitle: "PlayStation_Portable",
                    notes: [String(localized: "Use .iso or .cso dumps. RomsBox also installs PPSSPP's support files (fonts and data) into the BIOS folder.")]),
        .ps2: .init(manufacturer: "Sony", year: 2000, wikipediaTitle: "PlayStation_2",
                    notes: [String(localized: "PCSX2 needs a PS2 BIOS dump in the BIOS folder's pcsx2/bios folder (any region). Dumps work best as .chd or .iso.")]),
        .ps3: .init(manufacturer: "Sony", year: 2006, wikipediaTitle: "PlayStation_3",
                    controls: [String(localized: "RPCS3 uses its own controller setup. Configure it once in RPCS3 (Pads) — RomsBox's controller settings don't apply.")],
                    notes: [String(localized: "Install the PS3 system software once in RPCS3 (File › Install Firmware) with PS3UPDAT.PUP from Sony's website."), String(localized: "Games can be .iso files or game folders named like Game.ps3 (containing PS3_GAME).")]),
        .xbox: .init(manufacturer: "Microsoft", year: 2001, wikipediaTitle: "Xbox_(console)",
                    controls: [String(localized: "xemu uses its own controller setup — configure it once in xemu.")],
                    notes: [String(localized: "xemu needs the Xbox boot ROM (MCPX), a flash BIOS and a hard disk image. Set them once in xemu (Settings › System)."), String(localized: "Games must be xiso-format .iso dumps.")]),
        .msx: .init(manufacturer: "Microsoft, ASCII", year: 1983, wikipediaTitle: "MSX",
                    notes: [String(localized: "RomsBox installs blueMSX's machine and database files into the BIOS folder with the core.")]),
        .dos: .init(manufacturer: "Microsoft", year: 1981, wikipediaTitle: "MS-DOS",
                    notes: [String(localized: "Keep each game zipped (.zip or .dosz); DOSBox Pure runs it straight from the archive and asks which program to start the first time.")]),
        .wonderswan: .init(manufacturer: "Bandai", year: 1999, wikipediaTitle: "WonderSwan",
                    controls: [String(localized: "Games played vertically can be rotated in RetroArch's core options.")]),
        .wonderswancolor: .init(manufacturer: "Bandai", year: 2000, wikipediaTitle: "WonderSwan_Color",
                    controls: [String(localized: "Games played vertically can be rotated in RetroArch's core options.")]),
        .ngp: .init(manufacturer: "SNK", year: 1998, wikipediaTitle: "Neo_Geo_Pocket"),
        .ngpc: .init(manufacturer: "SNK", year: 1999, wikipediaTitle: "Neo_Geo_Pocket_Color"),
        .neogeocd: .init(manufacturer: "SNK", year: 1994, wikipediaTitle: "Neo_Geo_CD",
                    notes: [String(localized: "Use .chd or .cue/.bin dumps. The Neo Geo CD BIOS goes in a neocd folder inside the BIOS folder.")]),
        .atarist: .init(manufacturer: "Atari", year: 1985, wikipediaTitle: "Atari_ST"),
        .atari800: .init(manufacturer: "Atari", year: 1979, wikipediaTitle: "Atari_8-bit_computers"),
        .colecovision: .init(manufacturer: "Coleco", year: 1982, wikipediaTitle: "ColecoVision"),
        .intellivision: .init(manufacturer: "Mattel", year: 1979, wikipediaTitle: "Intellivision"),
        .vectrex: .init(manufacturer: "GCE", year: 1982, wikipediaTitle: "Vectrex"),
        .odyssey2: .init(manufacturer: "Magnavox, Philips", year: 1978, wikipediaTitle: "Magnavox_Odyssey_2"),
        .channelf: .init(manufacturer: "Fairchild", year: 1976, wikipediaTitle: "Fairchild_Channel_F"),
        .c64: .init(manufacturer: "Commodore", year: 1982, wikipediaTitle: "Commodore_64"),
        .amiga: .init(manufacturer: "Commodore", year: 1985, wikipediaTitle: "Amiga",
                    notes: [String(localized: "Use .adf disks, or .lha/WHDLoad packs for hard-disk installs.")]),
        .zxspectrum: .init(manufacturer: "Sinclair", year: 1982, wikipediaTitle: "ZX_Spectrum"),
        .amstradcpc: .init(manufacturer: "Amstrad", year: 1984, wikipediaTitle: "Amstrad_CPC"),
        .mame: .init(manufacturer: "MAME team", year: 1997, wikipediaTitle: "MAME",
                    controls: [String(localized: "Select inserts a coin, Start starts the game.")],
                    notes: [String(localized: "Keep each game zipped with its romset name. Romsets must match the MAME version of the core you use.")]),
        .fbneo: .init(manufacturer: "FinalBurn Neo team", year: 2019, wikipediaTitle: "FinalBurn_Neo",
                    controls: [String(localized: "Select inserts a coin, Start starts the game.")],
                    notes: [String(localized: "Keep each game zipped with its romset name. Romsets must match FinalBurn Neo's version (1.0.0.03).")]),
        .triforce: .init(manufacturer: "Namco, Sega, Nintendo", year: 2002, wikipediaTitle: "Triforce_(arcade_board)",
                         controls: [String(localized: "Dolphin uses its own controller setup. Configure it once in Dolphin (Controllers › Triforce) — RomsBox's controller settings don't apply.")],
                         notes: [String(localized: "Triforce games run in Dolphin, the GameCube and Wii emulator, which now includes Triforce support. Use .iso, .gcz or .rvz dumps."),
                                 String(localized: "A Dolphin already in your Applications folder is used as is; otherwise RomsBox installs the latest release from dolphin-emu.org.")])
    ]
}

/// The general (non-system) help pages.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, emulators, controller, bigBox, scraping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: String(localized: "Getting Started")
        case .emulators: String(localized: "Emulators & BIOS")
        case .controller: String(localized: "Controller")
        case .bigBox: String(localized: "Big Box")
        case .scraping: String(localized: "Game Info & Art")
        }
    }

    var symbolName: String {
        switch self {
        case .gettingStarted: "star"
        case .emulators: "arcade.stick.console"
        case .controller: "gamecontroller"
        case .bigBox: "tv"
        case .scraping: "photo.on.rectangle.angled"
        }
    }

    /// Each section: a heading and its paragraphs.
    var sections: [(heading: String, paragraphs: [String])] {
        switch self {
        case .gettingStarted:
            [
                (String(localized: "Your ROMs folder"), [
                    String(localized: "RomsBox reads ROMs folders organized the way Batocera, RetroBat and ES-DE do it: one subfolder per system, named after the system (snes, megadrive, neogeo…). Each system's help page lists the folder names it recognizes."),
                    String(localized: "Add your folder in Settings › General, then choose Rescan Library. Rescan again whenever you add or remove games.")
                ]),
                (String(localized: "Names and artwork"), [
                    String(localized: "Game names, descriptions and artwork already in a gamelist.xml (from ES-DE, Batocera or RetroBat) and in downloaded_media or a system's images and videos folders are picked up automatically. Arcade games get their real titles from FinalBurn Neo's game list."),
                    String(localized: "For anything still missing, see Game Info & Art.")
                ]),
                (String(localized: "Playing Games"), [
                    String(localized: "Double-click a game, press ⌘↩, or press the confirm button on a controller. The first time, set up emulators in Settings › Emulators — Set Up All Systems installs the recommended one for every system in your library.")
                ])
            ]
        case .emulators:
            [
                (String(localized: "The Emulation folder"), [
                    String(localized: "Everything emulation-related lives in one folder: BIOS files, saves and save states (per system), RetroArch's cores and settings, and the emulators RomsBox installs. Back it up or copy it to another Mac to take everything with you. Change its location in Settings › General.")
                ]),
                (String(localized: "Installing emulators"), [
                    String(localized: "RomsBox downloads emulators from their official sources only: RetroArch and its cores from libretro's buildbot, standalone emulators from their own release pages. Each system's page lists the recommended emulator first."),
                    String(localized: "Cores and emulators you installed yourself are detected too. Settings › Emulators also checks for core updates.")
                ]),
                (String(localized: "BIOS files"), [
                    String(localized: "Some systems need the console's BIOS. These files are copyrighted, so RomsBox never downloads them: dump them from hardware you own and put them in the Emulation folder's BIOS folder. Each system's page shows which files it needs and whether they're there.")
                ]),
                (String(localized: "Custom emulators"), [
                    String(localized: "Any other emulator can be added in Settings › Emulators › Custom Emulators, with its command-line arguments, then chosen per system or per game (Launch With).")
                ])
            ]
        case .controller:
            [
                (String(localized: "Layout"), [
                    String(localized: "Settings › Controller sets which button confirms: the bottom one (Xbox, PlayStation) or the right one (Nintendo, Switch). It applies to RomsBox, Big Box and RetroArch's menus.")
                ]),
                (String(localized: "In games"), [
                    String(localized: "By default games use buttons by position, like the console's own pad. Button mapping changes which of your controller's buttons does what in RetroArch games, for every player. Select + Start quits a game in RetroArch and DuckStation."),
                    String(localized: "Save your setup as a profile to switch back to it later; profiles are kept in the Emulation folder.")
                ]),
                (String(localized: "In the library"), [
                    String(localized: "D-pad or left stick: browse. Confirm: play. Y / Triangle: favorite. LB / RB: previous or next system. Menu / Start: Big Box.")
                ])
            ]
        case .bigBox:
            [
                (String(localized: "Couch mode"), [
                    String(localized: "Big Box is a full-screen view made for the TV and a controller. Open it with ⌘⇧B, the Big Box toolbar button, or Menu / Start on a controller; leave it with the back button."),
                    String(localized: "To always start in Big Box, turn on Open Big Box at launch in Settings › General.")
                ])
            ]
        case .scraping:
            [
                (String(localized: "Scraping"), [
                    String(localized: "RomsBox can fetch descriptions, release dates and artwork from ScreenScraper or TheGamesDB. ScreenScraper matches games exactly by file; TheGamesDB searches by title."),
                    String(localized: "Add credentials in Settings › ScreenScraper or TheGamesDB, then use Scrape Missing in the toolbar, or Scrape Info on a single game.")
                ])
            ]
        }
    }
}
