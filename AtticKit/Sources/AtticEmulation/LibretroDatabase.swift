import Foundation
import AtticModels

/// libretro's canonical database names (the `database` field in core
/// `.info` files) for each system Attic knows. A core's `database` list
/// names *every* system it runs — Genesis Plus GX lists Game Gear, Master
/// System, Mega-CD and Mega Drive — which its single `systemid` can't.
/// Names verified against libretro's current info files.
public enum LibretroDatabase {
    static let namesBySystem: [CanonicalSystemID: [String]] = [
        .nes: ["Nintendo - Nintendo Entertainment System"],
        .snes: ["Nintendo - Super Nintendo Entertainment System"],
        .gba: ["Nintendo - Game Boy Advance"],
        .genesis: ["Sega - Mega Drive - Genesis"],
        .mastersystem: ["Sega - Master System - Mark III"],
        .gamegear: ["Sega - Game Gear"],
        .segacd: ["Sega - Mega-CD - Sega CD"],
        .sega32x: ["Sega - 32X"],
        .saturn: ["Sega - Saturn"],
        .dreamcast: ["Sega - Dreamcast"],
        .psx: ["Sony - PlayStation"],
        .atari2600: ["Atari - 2600"],
        .atari5200: ["Atari - 5200"],
        .atari7800: ["Atari - 7800"],
        .atarilynx: ["Atari - Lynx"],
        .atarijaguar: ["Atari - Jaguar"],
        .pcengine: ["NEC - PC Engine - TurboGrafx 16"],
        .pcenginecd: ["NEC - PC Engine CD - TurboGrafx-CD"],
        .supergrafx: ["NEC - PC Engine SuperGrafx"],
        .pcfx: ["NEC - PC-FX"],
        .threedo: ["The 3DO Company - 3DO"],
        .cdi: ["Philips - CD-i"],
        .virtualboy: ["Nintendo - Virtual Boy"],
        .neogeo: ["SNK - Neo Geo"],
        .gb: ["Nintendo - Game Boy"],
        .gbc: ["Nintendo - Game Boy Color"],
        .n64: ["Nintendo - Nintendo 64"],
        .nds: ["Nintendo - Nintendo DS"],
        .n3ds: ["Nintendo - Nintendo 3DS"],
        .gamecube: ["Nintendo - GameCube"],
        .wii: ["Nintendo - Wii"],
        .wiiu: ["Nintendo - Wii U"],
        .fds: ["Nintendo - Family Computer Disk System"],
        .pokemini: ["Nintendo - Pokemon Mini"],
        .gameandwatch: ["Handheld Electronic Game"],
        .sg1000: ["Sega - SG-1000"],
        .naomi: ["Sega - Naomi"],
        .naomi2: ["Sega - Naomi 2"],
        .stv: ["Sega - ST-V"],
        .n64dd: ["Nintendo - Nintendo 64DD"],
        .satellaview: ["Nintendo - Satellaview"],
        .sufami: ["Nintendo - Sufami Turbo"],
        .atomiswave: ["Atomiswave"],
        .model3: ["Sega - Model 3"],
        .psp: ["Sony - PlayStation Portable"],
        .ps2: ["Sony - PlayStation 2"],
        .ps3: ["Sony - PlayStation 3"],
        .scummvm: ["ScummVM"],
        .doom: ["DOOM"],
        .quake: ["Quake"],
        .easyrpg: ["RPG Maker"],
        .x68000: ["Sharp - X68000"],
        .pc88: ["NEC - PC-88"],
        .pc98: ["NEC - PC-98"],
        .pico8: ["PICO-8"],
        .tic80: ["TIC-80"],
        .wasm4: ["WASM-4"],
        .arduboy: ["Arduboy Inc - Arduboy"],
        .vic20: ["Commodore - VIC-20"],
        .plus4: ["Commodore - Plus-4"],
        .zx81: ["Sinclair - ZX 81"],
        .msx: ["Microsoft - MSX", "Microsoft - MSX2"],
        .dos: ["DOS"],
        .wonderswan: ["Bandai - WonderSwan"],
        .wonderswancolor: ["Bandai - WonderSwan Color"],
        .ngp: ["SNK - Neo Geo Pocket"],
        .ngpc: ["SNK - Neo Geo Pocket Color"],
        .neogeocd: ["SNK - Neo Geo CD"],
        .atarist: ["Atari - ST"],
        .atari800: ["Atari - 8-bit Family"],
        .colecovision: ["Coleco - ColecoVision"],
        .intellivision: ["Mattel - Intellivision"],
        .vectrex: ["GCE - Vectrex"],
        .odyssey2: ["Magnavox - Odyssey2", "Philips - Videopac+"],
        .channelf: ["Fairchild - Channel F"],
        .c64: ["Commodore - 64"],
        .amiga: ["Commodore - Amiga"],
        .zxspectrum: ["Sinclair - ZX Spectrum", "Sinclair - ZX Spectrum +3"],
        .amstradcpc: ["Amstrad - CPC"],
        .mame: ["MAME"]
    ]

    private static let systemByName: [String: CanonicalSystemID] = {
        var map: [String: CanonicalSystemID] = [:]
        for (system, names) in namesBySystem {
            for name in names { map[name] = system }
        }
        return map
    }()

    public static func system(forDatabaseName name: String) -> CanonicalSystemID? {
        systemByName[name]
    }
}
