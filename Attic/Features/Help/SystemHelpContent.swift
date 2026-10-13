import Foundation
import AtticModels

/// The hand-written part of each system's help page. Everything else on the
/// page (ROM folder, file types, emulators, BIOS) comes from the system
/// taxonomy, the emulator catalog and the core info files, so it can't
/// drift from what Attic actually does.
struct SystemHelpInfo {
    let manufacturer: String
    let year: Int
    /// English Wikipedia article title.
    let wikipediaTitle: String
    /// Resources rather than strings, so the ROMs folders' _sysinfo.txt
    /// can have them in English whatever the app's language.
    var controls: [LocalizedStringResource] = []
    var notes: [LocalizedStringResource] = []

    var wikipediaURL: URL {
        URL(string: "https://en.wikipedia.org/wiki/")!.appending(path: wikipediaTitle)
    }
}

enum SystemHelpContent {
    static func info(for system: CanonicalSystemID) -> SystemHelpInfo? {
        byID[system.baseSystem]
    }

    private static let discNote = LocalizedStringResource("Disc images work best as .chd — one compressed file per disc. For .cue/.bin dumps, keep each .cue next to its .bin files.")
    private static let multiDiscNote = LocalizedStringResource("For multi-disc games, list the discs in an .m3u playlist (one file name per line) and keep only the .m3u visible, so the emulator can swap discs.")
    private static let romsetNote = LocalizedStringResource("Keep each game zipped and named after its romset (for example mslug.zip). Don't unzip or rename them: arcade emulators find games by these names.")
    private static let fbneoVersionNote = LocalizedStringResource("Romsets must match FinalBurn Neo's version (1.0.0.03). Sets from other versions or from another emulator may fail to load.")
    private static let coinControls = LocalizedStringResource("Select inserts a coin, Start starts the game.")
    private static let sixButtonControls = LocalizedStringResource("Six-button fighting games use the four face buttons for light and medium attacks, and L and R for the strongest ones.")

    private static let byID: [CanonicalSystemID: SystemHelpInfo] = [
        .nes: .init(manufacturer: "Nintendo", year: 1983, wikipediaTitle: "Nintendo_Entertainment_System"),
        .snes: .init(manufacturer: "Nintendo", year: 1990, wikipediaTitle: "Super_Nintendo_Entertainment_System"),
        .gba: .init(manufacturer: "Nintendo", year: 2001, wikipediaTitle: "Game_Boy_Advance"),
        .virtualboy: .init(manufacturer: "Nintendo", year: 1995, wikipediaTitle: "Virtual_Boy",
                           controls: [LocalizedStringResource("The Virtual Boy's second D-pad is on the right stick.")],
                           notes: [LocalizedStringResource("Games show in red and black on a flat screen. Attic turns off the core's VR mode, which needs a kind of OpenGL macOS doesn't offer.")]),
        .genesis: .init(manufacturer: "Sega", year: 1988, wikipediaTitle: "Sega_Genesis",
                        controls: [LocalizedStringResource("Six-button games use the four face buttons plus L and R.")]),
        .mastersystem: .init(manufacturer: "Sega", year: 1985, wikipediaTitle: "Master_System"),
        .gamegear: .init(manufacturer: "Sega", year: 1990, wikipediaTitle: "Game_Gear"),
        .segacd: .init(manufacturer: "Sega", year: 1991, wikipediaTitle: "Sega_CD", notes: [discNote, multiDiscNote]),
        .sega32x: .init(manufacturer: "Sega", year: 1994, wikipediaTitle: "32X"),
        .saturn: .init(manufacturer: "Sega", year: 1994, wikipediaTitle: "Sega_Saturn", notes: [discNote, multiDiscNote]),
        .dreamcast: .init(manufacturer: "Sega", year: 1998, wikipediaTitle: "Dreamcast",
                          notes: [LocalizedStringResource("Dreamcast games work best as .chd or .gdi dumps. The BIOS files go in a dc folder inside the BIOS folder.")]),
        .psx: .init(manufacturer: "Sony", year: 1994, wikipediaTitle: "PlayStation_(console)", notes: [discNote, multiDiscNote]),
        .atari2600: .init(manufacturer: "Atari", year: 1977, wikipediaTitle: "Atari_2600"),
        .atari5200: .init(manufacturer: "Atari", year: 1982, wikipediaTitle: "Atari_5200"),
        .atari7800: .init(manufacturer: "Atari", year: 1986, wikipediaTitle: "Atari_7800"),
        .atarilynx: .init(manufacturer: "Atari", year: 1989, wikipediaTitle: "Atari_Lynx"),
        .atarijaguar: .init(manufacturer: "Atari", year: 1993, wikipediaTitle: "Atari_Jaguar",
                            controls: [LocalizedStringResource("The Jaguar's number pad isn't on modern controllers; games that need it map its keys to spare buttons.")]),
        .pcengine: .init(manufacturer: "NEC", year: 1987, wikipediaTitle: "TurboGrafx-16"),
        .pcenginecd: .init(manufacturer: "NEC", year: 1988, wikipediaTitle: "TurboGrafx-CD", notes: [discNote]),
        .supergrafx: .init(manufacturer: "NEC", year: 1989, wikipediaTitle: "PC_Engine_SuperGrafx"),
        .pcfx: .init(manufacturer: "NEC", year: 1994, wikipediaTitle: "PC-FX", notes: [discNote]),
        .threedo: .init(manufacturer: "The 3DO Company", year: 1993, wikipediaTitle: "3DO_Interactive_Multiplayer", notes: [discNote]),
        .cdi: .init(manufacturer: "Philips", year: 1991, wikipediaTitle: "CD-i", notes: [discNote]),
        .neogeo: .init(manufacturer: "SNK", year: 1990, wikipediaTitle: "Neo_Geo_(system)",
                       controls: [LocalizedStringResource("Neo Geo A, B, C and D are the bottom, right, left and top buttons."), coinControls],
                       notes: [romsetNote, fbneoVersionNote,
                               LocalizedStringResource("neogeo.zip (the Neo Geo BIOS set) goes in the BIOS folder, still zipped."),
                               LocalizedStringResource("Free play is on by default (Settings › General › Arcade), so Start begins a game without coins. Games first show the Neo Geo boot screen for about 10 seconds.")]),
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
                    controls: [LocalizedStringResource("The touch screen follows the mouse; click to touch.")]),
        .n3ds: .init(manufacturer: "Nintendo", year: 2011, wikipediaTitle: "Nintendo_3DS",
                    controls: [LocalizedStringResource("The touch screen follows the mouse; click to touch.")],
                    notes: [LocalizedStringResource("Use decrypted game dumps (.3ds, .cci or .cxi).")]),
        .gamecube: .init(manufacturer: "Nintendo", year: 2001, wikipediaTitle: "GameCube",
                    controls: [LocalizedStringResource("Dolphin uses its own controller setup. Configure it once in Dolphin (Controllers) — Attic's controller settings don't apply to the Dolphin app.")],
                    notes: [LocalizedStringResource("Dumps work best as .rvz (compressed, lossless) or .iso.")]),
        .wii: .init(manufacturer: "Nintendo", year: 2006, wikipediaTitle: "Wii",
                    controls: [LocalizedStringResource("Dolphin uses its own controller setup. Configure it once in Dolphin (Controllers) — Attic's controller settings don't apply to the Dolphin app.")],
                    notes: [LocalizedStringResource("Dumps work best as .rvz (compressed, lossless), .wbfs or .iso.")]),
        .wiiu: .init(manufacturer: "Nintendo", year: 2012, wikipediaTitle: "Wii_U",
                    notes: [LocalizedStringResource("Use .wua files (Cemu's compressed format), or .wud/.wux disc images.")]),
        .fds: .init(manufacturer: "Nintendo", year: 1986, wikipediaTitle: "Family_Computer_Disk_System",
                    controls: [LocalizedStringResource("Select switches the disk side in most games.")]),
        .pokemini: .init(manufacturer: "Nintendo", year: 2001, wikipediaTitle: "Pokémon_Mini"),
        .gameandwatch: .init(manufacturer: "Nintendo", year: 1980, wikipediaTitle: "Game_&_Watch",
                    notes: [LocalizedStringResource("Game & Watch games are .mgw files, converted from MAME's artwork and romsets.")]),
        .sg1000: .init(manufacturer: "Sega", year: 1983, wikipediaTitle: "SG-1000"),
        .naomi: .init(manufacturer: "Sega", year: 1998, wikipediaTitle: "Sega_NAOMI",
                    controls: [LocalizedStringResource("Select inserts a coin, Start starts the game.")],
                    notes: [LocalizedStringResource("Keep each game zipped with its MAME romset name. The NAOMI BIOS (naomi.zip) goes in a dc folder inside the BIOS folder.")]),
        .atomiswave: .init(manufacturer: "Sammy", year: 2003, wikipediaTitle: "Atomiswave",
                    controls: [LocalizedStringResource("Select inserts a coin, Start starts the game.")],
                    notes: [LocalizedStringResource("Keep each game zipped with its MAME romset name. The Atomiswave BIOS (awbios.zip) goes in a dc folder inside the BIOS folder.")]),
        .model3: .init(manufacturer: "Sega", year: 1996, wikipediaTitle: "Sega_Model_3",
                    controls: [LocalizedStringResource("Select inserts a coin, Start starts the game.")],
                    notes: [LocalizedStringResource("Keep each game zipped with its MAME romset name.")]),
        .psp: .init(manufacturer: "Sony", year: 2004, wikipediaTitle: "PlayStation_Portable",
                    notes: [LocalizedStringResource("Use .iso or .cso dumps. Attic also installs PPSSPP's support files (fonts and data) into the BIOS folder.")]),
        .ps2: .init(manufacturer: "Sony", year: 2000, wikipediaTitle: "PlayStation_2",
                    notes: [LocalizedStringResource("PCSX2 needs a PS2 BIOS dump in the BIOS folder's pcsx2/bios folder (any region). Dumps work best as .chd or .iso.")]),
        .ps3: .init(manufacturer: "Sony", year: 2006, wikipediaTitle: "PlayStation_3",
                    controls: [LocalizedStringResource("RPCS3 uses its own controller setup. Configure it once in RPCS3 (Pads) — Attic's controller settings don't apply.")],
                    notes: [LocalizedStringResource("Install the PS3 system software once in RPCS3 (File › Install Firmware) with PS3UPDAT.PUP from Sony's website."), LocalizedStringResource("Games can be .iso files or game folders named like Game.ps3 (containing PS3_GAME).")]),
        .ps4: .init(manufacturer: "Sony", year: 2013, wikipediaTitle: "PlayStation_4",
                    controls: [LocalizedStringResource("shadPS4 uses its own controller setup — Attic's controller settings don't apply.")],
                    notes: [LocalizedStringResource("shadPS4 is still young: many games don't start or run slowly yet. Its Mac version runs through Rosetta."), LocalizedStringResource("Games are dumped game folders (with eboot.bin inside), renamed like Game.ps4. Installed .pkg files aren't supported."), LocalizedStringResource("Some games need system modules dumped from your PS4, in shadPS4's sys_modules folder (~/Library/Application Support/shadPS4).")]),
        .psvita: .init(manufacturer: "Sony", year: 2011, wikipediaTitle: "PlayStation_Vita",
                    controls: [LocalizedStringResource("Vita3K uses its own controller setup. Configure it once in Vita3K (Controls) — Attic's controller settings don't apply.")],
                    notes: [LocalizedStringResource("Install the PS Vita firmware once in Vita3K (PSVUPDAT.PUP and the font package, both from Sony's website)."), LocalizedStringResource("Install your games in Vita3K (.vpk, or .pkg with its license). With a psvita folder in your ROMs folder, Attic adds every installed game to the library by itself."), LocalizedStringResource("Each game is a .psvita file holding its title ID, such as PCSE00120.")]),
        .scummvm: .init(manufacturer: "ScummVM", year: 2001, wikipediaTitle: "ScummVM",
                    notes: [LocalizedStringResource("Each game is a folder named like Monkey Island.scummvm holding the game's files and a file of the same name (Monkey Island.scummvm) containing ScummVM's ID for it, such as monkey.")]),
        .doom: .init(manufacturer: "id Software", year: 1993, wikipediaTitle: "Doom_(1993_video_game)",
                    notes: [LocalizedStringResource("Put the game's .wad files here: doom.wad, doom2.wad, or the free freedoom1.wad. Attic installs the prboom.wad PrBoom needs.")]),
        .quake: .init(manufacturer: "id Software", year: 1996, wikipediaTitle: "Quake_(video_game)",
                    notes: [LocalizedStringResource("The game is a folder named like Quake.quake with Quake's id1 folder inside (id1/pak0.pak, and pak1.pak for the full game).")]),
        .easyrpg: .init(manufacturer: "ASCII, Enterbrain", year: 2000, wikipediaTitle: "RPG_Maker",
                    notes: [LocalizedStringResource("Each game is a .zip, or a folder named like Game.easyrpg with its RPG_RT.ldb inside.")]),
        .x68000: .init(manufacturer: "Sharp", year: 1987, wikipediaTitle: "X68000"),
        .pc88: .init(manufacturer: "NEC", year: 1981, wikipediaTitle: "PC-8800_series"),
        .pc98: .init(manufacturer: "NEC", year: 1982, wikipediaTitle: "PC-9800_series"),
        .pico8: .init(manufacturer: "Lexaloffle", year: 2015, wikipediaTitle: "Pico-8",
                    notes: [LocalizedStringResource("Carts are .p8 or .p8.png files, from the PICO-8 website (Splore) or itch.io. Retro8 runs most of them; the official PICO-8 app runs all.")]),
        .tic80: .init(manufacturer: "Nesbox", year: 2017, wikipediaTitle: "TIC-80"),
        .wasm4: .init(manufacturer: "Aduros", year: 2021, wikipediaTitle: "WebAssembly",
                    notes: [LocalizedStringResource("Games are .wasm files, from wasm4.org.")]),
        .arduboy: .init(manufacturer: "Arduboy", year: 2016, wikipediaTitle: "Arduboy",
                    notes: [LocalizedStringResource("Games are .hex files. A .arduboy download is a zip: take the .hex out of it.")]),
        .vic20: .init(manufacturer: "Commodore", year: 1980, wikipediaTitle: "Commodore_VIC-20"),
        .plus4: .init(manufacturer: "Commodore", year: 1984, wikipediaTitle: "Commodore_Plus/4"),
        .c128: .init(manufacturer: "Commodore", year: 1985, wikipediaTitle: "Commodore_128"),
        .zx81: .init(manufacturer: "Sinclair", year: 1981, wikipediaTitle: "ZX81"),
        .macintosh: .init(manufacturer: "Apple", year: 1984, wikipediaTitle: "Macintosh",
                    notes: [LocalizedStringResource("Mini vMac needs a Mac II ROM (MacII.ROM) and a system disk: games and System 6/7 go on .dsk disk images.")]),
        .xbox: .init(manufacturer: "Microsoft", year: 2001, wikipediaTitle: "Xbox_(console)",
                    controls: [LocalizedStringResource("xemu uses its own controller setup — configure it once in xemu.")],
                    notes: [LocalizedStringResource("xemu needs the Xbox boot ROM (MCPX), a flash BIOS and a hard disk image. Set them once in xemu (Settings › System)."), LocalizedStringResource("Games must be xiso-format .iso dumps.")]),
        .msx: .init(manufacturer: "Microsoft, ASCII", year: 1983, wikipediaTitle: "MSX",
                    notes: [LocalizedStringResource("Attic installs blueMSX's machine and database files into the BIOS folder with the core.")]),
        .dos: .init(manufacturer: "Microsoft", year: 1981, wikipediaTitle: "MS-DOS",
                    notes: [LocalizedStringResource("Keep each game zipped (.zip or .dosz); DOSBox Pure runs it straight from the archive and asks which program to start the first time.")]),
        .wonderswan: .init(manufacturer: "Bandai", year: 1999, wikipediaTitle: "WonderSwan",
                    controls: [LocalizedStringResource("Games played vertically can be rotated in RetroArch's core options.")]),
        .wonderswancolor: .init(manufacturer: "Bandai", year: 2000, wikipediaTitle: "WonderSwan_Color",
                    controls: [LocalizedStringResource("Games played vertically can be rotated in RetroArch's core options.")]),
        .ngp: .init(manufacturer: "SNK", year: 1998, wikipediaTitle: "Neo_Geo_Pocket"),
        .ngpc: .init(manufacturer: "SNK", year: 1999, wikipediaTitle: "Neo_Geo_Pocket_Color"),
        .neogeocd: .init(manufacturer: "SNK", year: 1994, wikipediaTitle: "Neo_Geo_CD",
                    notes: [LocalizedStringResource("Use .chd or .cue/.bin dumps. The Neo Geo CD BIOS goes in a neocd folder inside the BIOS folder.")]),
        .atarist: .init(manufacturer: "Atari", year: 1985, wikipediaTitle: "Atari_ST"),
        .atari800: .init(manufacturer: "Atari", year: 1979, wikipediaTitle: "Atari_8-bit_computers"),
        .colecovision: .init(manufacturer: "Coleco", year: 1982, wikipediaTitle: "ColecoVision"),
        .intellivision: .init(manufacturer: "Mattel", year: 1979, wikipediaTitle: "Intellivision"),
        .vectrex: .init(manufacturer: "GCE", year: 1982, wikipediaTitle: "Vectrex"),
        .odyssey2: .init(manufacturer: "Magnavox, Philips", year: 1978, wikipediaTitle: "Magnavox_Odyssey_2"),
        .channelf: .init(manufacturer: "Fairchild", year: 1976, wikipediaTitle: "Fairchild_Channel_F"),
        .c64: .init(manufacturer: "Commodore", year: 1982, wikipediaTitle: "Commodore_64"),
        .amiga: .init(manufacturer: "Commodore", year: 1985, wikipediaTitle: "Amiga",
                    notes: [LocalizedStringResource("Use .adf disks, or .lha/WHDLoad packs for hard-disk installs.")]),
        .zxspectrum: .init(manufacturer: "Sinclair", year: 1982, wikipediaTitle: "ZX_Spectrum"),
        .amstradcpc: .init(manufacturer: "Amstrad", year: 1984, wikipediaTitle: "Amstrad_CPC"),
        .mame: .init(manufacturer: "MAME team", year: 1997, wikipediaTitle: "MAME",
                    controls: [LocalizedStringResource("Select inserts a coin, Start starts the game.")],
                    notes: [LocalizedStringResource("Keep each game zipped with its romset name. Romsets must match the MAME version of the core you use.")]),
        .fbneo: .init(manufacturer: "FinalBurn Neo team", year: 2019, wikipediaTitle: "FinalBurn_Neo",
                    controls: [LocalizedStringResource("Select inserts a coin, Start starts the game.")],
                    notes: [LocalizedStringResource("Keep each game zipped with its romset name. Romsets must match FinalBurn Neo's version (1.0.0.03).")]),
        .triforce: .init(manufacturer: "Namco, Sega, Nintendo", year: 2002, wikipediaTitle: "Triforce_(arcade_board)",
                         controls: [LocalizedStringResource("Dolphin uses its own controller setup. Configure it once in Dolphin (Controllers › Triforce) — Attic's controller settings don't apply.")],
                         notes: [LocalizedStringResource("Triforce games run in Dolphin, the GameCube and Wii emulator, which now includes Triforce support. Use .iso, .gcz or .rvz dumps."),
                                 LocalizedStringResource("A Dolphin already in your Applications folder is used as is; otherwise Attic installs the latest release from dolphin-emu.org.")])
    ]
}

/// The general (non-system) help pages.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, emulators, controller, cabinet, scraping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: String(localized: "Getting Started")
        case .emulators: String(localized: "Emulators & BIOS")
        case .controller: String(localized: "Controller")
        case .cabinet: String(localized: "Cabinet Mode")
        case .scraping: String(localized: "Game Info & Art")
        }
    }

    var symbolName: String {
        switch self {
        case .gettingStarted: "star"
        case .emulators: "arcade.stick.console"
        case .controller: "gamecontroller"
        case .cabinet: "tv"
        case .scraping: "photo.on.rectangle.angled"
        }
    }

    /// Each section: a heading and its paragraphs.
    var sections: [(heading: String, paragraphs: [String])] {
        switch self {
        case .gettingStarted:
            [
                (String(localized: "Your ROMs folder"), [
                    String(localized: "Attic reads ROMs folders organized the way Batocera, RetroBat and ES-DE do it: one subfolder per system, named after the system (snes, megadrive, neogeo…). Each system's help page lists the folder names it recognizes."),
                    String(localized: "Add your folder in Settings › General, then choose Rescan Library. Rescan again whenever you add or remove games.")
                ]),
                (String(localized: "Names and artwork"), [
                    String(localized: "Game names, descriptions and artwork already in a gamelist.xml (from ES-DE, Batocera or RetroBat) and in a Media folder (ES-DE's downloaded_media) or a system's images and videos folders are picked up automatically. Arcade games get their real titles from FinalBurn Neo's game list."),
                    String(localized: "For anything still missing, see Game Info & Art.")
                ]),
                (String(localized: "Playing Games"), [
                    String(localized: "Double-click a game, press ⌘↩, or press the confirm button on a controller. The first time, set up emulators in Settings › Emulators — Set Up All Systems installs the recommended one for every system in your library.")
                ])
            ]
        case .emulators:
            [
                (String(localized: "The Emulation folder"), [
                    String(localized: "Everything emulation-related lives in one folder: BIOS files, saves and save states (per system), RetroArch's cores and settings, and the emulators Attic installs. Back it up or copy it to another Mac to take everything with you. Change its location in Settings › General.")
                ]),
                (String(localized: "Installing emulators"), [
                    String(localized: "Attic downloads emulators from their official sources only: RetroArch and its cores from libretro's buildbot, standalone emulators from their own release pages. Each system's page lists the recommended emulator first."),
                    String(localized: "Cores and emulators you installed yourself are detected too. Settings › Emulators also checks for core updates.")
                ]),
                (String(localized: "BIOS files"), [
                    String(localized: "Some systems need the console's BIOS. These files are copyrighted, so Attic never downloads them: dump them from hardware you own and put them in the Emulation folder's BIOS folder. Each system's page shows which files it needs and whether they're there.")
                ]),
                (String(localized: "Custom emulators"), [
                    String(localized: "Any other emulator can be added in Settings › Emulators › Custom Emulators, with its command-line arguments, then chosen per system or per game (Launch With).")
                ])
            ]
        case .controller:
            [
                (String(localized: "Layout"), [
                    String(localized: "Settings › Controller sets which button confirms: the bottom one (Xbox, PlayStation) or the right one (Nintendo, Switch). It applies to Attic, Cabinet Mode and RetroArch's menus.")
                ]),
                (String(localized: "In games"), [
                    String(localized: "By default games use buttons by position, like the console's own pad. Button mapping changes which of your controller's buttons does what in RetroArch games, for every player. Select + Start quits a game in RetroArch and DuckStation."),
                    String(localized: "Save your setup as a profile to switch back to it later; profiles are kept in the Emulation folder.")
                ]),
                (String(localized: "In the library"), [
                    String(localized: "D-pad or left stick: browse. Confirm: play. Y / Triangle: favorite. LB / RB: previous or next system. Menu / Start: Cabinet Mode.")
                ])
            ]
        case .cabinet:
            [
                (String(localized: "Couch mode"), [
                    String(localized: "Cabinet Mode is a full-screen view made for the TV and a controller. Open it with ⌘⇧B, the Cabinet Mode toolbar button, or Menu / Start on a controller; leave it with the back button."),
                    String(localized: "To always start in Cabinet Mode, turn on Open Cabinet Mode at launch in Settings › General.")
                ])
            ]
        case .scraping:
            [
                (String(localized: "Scraping"), [
                    String(localized: "Attic can fetch descriptions, release dates and artwork from ScreenScraper or TheGamesDB. ScreenScraper matches games exactly by file; TheGamesDB searches by title."),
                    String(localized: "Add credentials in Settings › ScreenScraper or TheGamesDB, then use Scrape Missing in the toolbar, or Scrape Info on a single game.")
                ])
            ]
        }
    }
}
