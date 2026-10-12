import Foundation

/// The file types each system's games come in — what the library scanner
/// lists, so stray files in a ROM folder (readmes, saves, a calculator
/// program) don't show up as games.
///
/// Generated from ES-DE's macOS `es_systems.xml` (the same lists ES-DE
/// writes into each folder's `systeminfo.txt`), merging every ES-DE system
/// whose short name RomsBox maps to the system:
/// https://gitlab.com/es-de/emulationstation-de/-/blob/master/resources/systems/macos/es_systems.xml
public enum SystemROMExtensions {
    static let byCanonicalID: [CanonicalSystemID: Set<String>] = [
        .nes: ["3dsen", "7z", "fds", "nes", "unf", "unif", "zip"],
        .snes: ["7z", "bin", "bml", "bs", "bsx", "dx2", "fig", "gd3", "gd7", "mgd", "sfc", "smc", "st", "swc", "zip"],
        .genesis: ["32x", "68k", "7z", "bin", "bms", "chd", "cue", "gen", "gg", "iso", "m3u", "md", "mdx", "sg", "sgd", "smd", "sms", "zip"],
        .psx: ["7z", "bin", "cbn", "ccd", "chd", "cue", "ecm", "exe", "img", "iso", "m3u", "mdf", "mds", "minipsf", "pbp", "psexe", "psf", "toc", "z", "zip", "znx"],
        .gba: ["7z", "agb", "bin", "cgb", "dmg", "gb", "gba", "gbc", "gbx", "sgb", "zip"],
        .mastersystem: ["68k", "7z", "bin", "bms", "chd", "col", "cue", "gen", "gg", "iso", "m3u", "md", "mdx", "rom", "sg", "sgd", "smd", "sms", "zip"],
        .gamegear: ["68k", "7z", "bin", "bms", "chd", "col", "cue", "gen", "gg", "iso", "m3u", "md", "mdx", "rom", "sg", "sgd", "smd", "sms", "zip"],
        .segacd: ["68k", "7z", "bin", "bms", "chd", "cue", "gen", "gg", "iso", "m3u", "md", "mdx", "sg", "sgd", "smd", "sms", "zip"],
        .saturn: ["7z", "bin", "ccd", "chd", "cue", "iso", "m3u", "mds", "toc", "zip"],
        .dreamcast: ["7z", "cdi", "chd", "cue", "dat", "elf", "gdi", "iso", "lst", "m3u", "zip"],
        .sega32x: ["32x", "68k", "7z", "bin", "chd", "cue", "gen", "iso", "m3u", "md", "smd", "sms", "zip"],
        .atari2600: ["7z", "a26", "bin", "zip"],
        .atari5200: ["7z", "a52", "atr", "atx", "bin", "car", "cas", "cdm", "com", "rom", "xex", "xfd", "zip"],
        .atari7800: ["7z", "a78", "bin", "zip"],
        .atarilynx: ["7z", "lnx", "lyx", "o", "zip"],
        .atarijaguar: ["7z", "abs", "bin", "cdi", "cof", "cue", "j64", "jag", "prg", "rom", "zip"],
        .pcengine: ["7z", "ccd", "chd", "cue", "img", "iso", "m3u", "pce", "rom", "sgx", "toc", "zip"],
        .pcenginecd: ["7z", "ccd", "chd", "cue", "img", "iso", "m3u", "pce", "sgx", "toc", "zip"],
        .pcfx: ["7z", "ccd", "chd", "cue", "m3u", "toc", "zip"],
        .supergrafx: ["7z", "ccd", "chd", "cue", "pce", "rom", "sgx", "zip"],
        .threedo: ["7z", "bin", "chd", "cue", "iso", "zip"],
        .cdi: ["chd", "cue", "iso"],
        .virtualboy: ["7z", "bin", "vb", "vboy", "zip"],
        .neogeo: ["7z", "neo", "zip"],
        .cps1: ["7z", "zip"],
        .cps2: ["7z", "zip"],
        .cps3: ["7z", "zip"],
        .triforce: ["7z", "ciso", "dff", "dol", "elf", "gcm", "gcz", "iso", "json", "m3u", "rvz", "tgc", "wad", "wbfs", "wia", "zip"],
        .gb: ["7z", "bs", "cgb", "dmg", "gb", "gbc", "gbx", "sfc", "sgb", "smc", "zip"],
        .gbc: ["7z", "bs", "cgb", "dmg", "gb", "gbc", "gbx", "sfc", "sgb", "smc", "zip"],
        .n64: ["7z", "app", "bin", "d64", "n64", "ndd", "u1", "v64", "z64", "zip"],
        .nds: ["7z", "app", "bin", "dsi", "ids", "nds", "zip"],
        .n3ds: ["3ds", "3dsx", "7z", "app", "axf", "cci", "cxi", "elf", "z3dsx", "zcci", "zcxi", "zip"],
        .gamecube: ["7z", "ciso", "dff", "dol", "elf", "gcm", "gcz", "iso", "json", "m3u", "rvz", "tgc", "wad", "wbfs", "wia", "zip"],
        .wii: ["7z", "ciso", "dff", "dol", "elf", "gcm", "gcz", "iso", "json", "m3u", "rvz", "tgc", "wad", "wbfs", "wia", "zip"],
        .wiiu: ["elf", "rpx", "tmd", "wua", "wud", "wuhb", "wux"],
        .fds: ["7z", "fds", "nes", "unf", "unif", "zip"],
        .pokemini: ["7z", "min", "zip"],
        .gameandwatch: ["7z", "mgw", "zip"],
        .sg1000: ["68k", "7z", "bin", "bms", "chd", "cue", "gen", "gg", "iso", "m3u", "md", "mdx", "ri", "rom", "sg", "sgd", "smd", "sms", "zip"],
        .naomi: ["7z", "bin", "dat", "elf", "lst", "zip"],
        .atomiswave: ["7z", "bin", "dat", "elf", "lst", "zip"],
        .model3: ["7z", "zip"],
        .psp: ["7z", "chd", "cso", "elf", "iso", "pbp", "prx", "zip"],
        .ps2: ["bin", "chd", "ciso", "cso", "dump", "elf", "gz", "img", "iso", "isz", "m3u", "mdf", "ngr", "nrg", "zso"],
        .ps3: ["app", "iso", "ps3", "ps3dir"],
        .xbox: ["iso", "xiso"],
        .msx: ["7z", "cas", "col", "di1", "di2", "dmk", "dsk", "fd1", "fd2", "m3u", "mx1", "mx2", "ogv", "ri", "rom", "sc", "sg", "wav", "xsa", "zip"],
        .dos: ["7z", "bat", "com", "conf", "cue", "dosz", "exe", "img", "iso", "zip"],
        .wonderswan: ["7z", "pc2", "ws", "zip"],
        .wonderswancolor: ["7z", "pc2", "ws", "wsc", "zip"],
        .ngp: ["7z", "ngc", "ngp", "ngpc", "npc", "zip"],
        .ngpc: ["7z", "ngc", "ngp", "ngpc", "npc", "zip"],
        .neogeocd: ["chd", "cue"],
        .atarist: ["7z", "dim", "ipf", "m3u", "msa", "st", "stx", "zip"],
        .atari800: ["7z", "a52", "atr", "atx", "bin", "car", "cas", "cdm", "com", "rom", "xex", "xfd", "zip"],
        .colecovision: ["7z", "bin", "cas", "col", "cv", "dsk", "m3u", "mx1", "mx2", "myv", "ri", "rom", "sc", "sg", "zip"],
        .intellivision: ["7z", "bin", "int", "rom", "zip"],
        .vectrex: ["7z", "bin", "gam", "vc", "vec", "zip"],
        .odyssey2: ["7z", "bin", "zip"],
        .channelf: ["7z", "bin", "chf", "zip"],
        .c64: ["7z", "bin", "cmd", "crt", "d2m", "d4m", "d64", "d6z", "d71", "d7z", "d80", "d81", "d82", "d8z", "g41", "g4z", "g64", "g6z", "gz", "lnx", "m3u", "nbz", "nib", "p00", "prg", "t64", "tap", "vfl", "vsf", "x64", "x6z", "zip"],
        .amiga: ["7z", "adf", "adz", "ccd", "chd", "cue", "dms", "fdi", "hdf", "hdz", "ipf", "iso", "lha", "m3u", "mds", "nrg", "rp9", "uae", "zip"],
        .zxspectrum: ["7z", "dsk", "gz", "img", "mgt", "rzx", "scl", "sh", "sna", "szx", "tap", "trd", "tzx", "udi", "z80", "zip"],
        .amstradcpc: ["7z", "cdt", "cpr", "dsk", "kcr", "m3u", "sna", "tap", "tar", "voc", "zip"],
        .mame: ["7z", "acgame", "app", "arcadedef", "cmd", "neo", "sh", "zip"],
        .fbneo: ["7z", "iso", "zip"],
    ]

    /// Lowercased extensions without the dot; `nil` for a system with no
    /// list, whose folders are taken as they are.
    public static func extensions(for systemID: CanonicalSystemID) -> Set<String>? {
        byCanonicalID[systemID]
    }

    /// Whether a file (or `.ps3`-style game folder) at this path, relative
    /// to the system folder, is one of the system's games.
    public static func accepts(_ romRelativePath: String, for systemID: CanonicalSystemID) -> Bool {
        guard let extensions = byCanonicalID[systemID] else { return true }
        let ext = (romRelativePath as NSString).pathExtension.lowercased()
        return extensions.contains(ext)
    }
}
