import AtticModels

/// TheGamesDB's own numeric platform id, a vocabulary independent of both
/// ScreenScraper's `systemeid` and `SystemTaxonomy`. Confirmed against
/// TheGamesDB's public platform listing/community references (no official
/// machine-readable schema is published).
public enum TheGamesDBSystemID {
    private static let byCanonicalID: [CanonicalSystemID: Int] = [
        .nes: 7,
        .snes: 6,
        .genesis: 18,
        .psx: 10,
        .gba: 5,
        .mastersystem: 35,
        .gamegear: 20,
        .segacd: 21,
        .saturn: 17,
        .dreamcast: 16,
        .sega32x: 33,
        .atari2600: 22,
        .atari5200: 26,
        .atari7800: 27,
        .atarilynx: 4924,
        .atarijaguar: 28,
        .pcengine: 34,
        .virtualboy: 4918,
        .neogeo: 24,
        .gb: 4,
        .gbc: 41,
        .n64: 3,
        .nds: 8,
        .n3ds: 4912,
        .gamecube: 2,
        .wii: 9,
        .wiiu: 38,
        .fds: 4936,
        .pokemini: 4957,
        .gameandwatch: 4950,
        .sg1000: 4949,
        .naomi: 23,
        .atomiswave: 23,
        .model3: 23,
        .psp: 13,
        .ps2: 11,
        .ps3: 12,
        .xbox: 14,
        .msx: 4929,
        .dos: 1,
        .wonderswan: 4925,
        .wonderswancolor: 4926,
        .ngp: 4922,
        .ngpc: 4923,
        .neogeocd: 4956,
        .atarist: 4937,
        .atari800: 4943,
        .colecovision: 31,
        .intellivision: 32,
        .vectrex: 4939,
        .odyssey2: 4927,
        .c64: 40,
        .amiga: 4911,
        .zxspectrum: 4913,
        .amstradcpc: 4914,
        .mame: 23,
        .fbneo: 23,
        // TheGamesDB files every CPS game under its generic Arcade platform.
        .cps1: 23, .cps2: 23, .cps3: 23,
        // TheGamesDB has no Triforce platform; its generic Arcade one works
        // since matching is by title.
        .triforce: 23,
        .pcenginecd: 4955,
        .pcfx: 4930,
        // No SuperGrafx entry: confirmed TheGamesDB has no distinct
        // platform for it (its full alphabetical platform list has no
        // "SuperGrafx" entry, only TurboGrafx-16/TurboGrafx-CD) — leaving
        // it unmapped rather than guessing an ID or reusing TG16's.
        .threedo: 25,
        .cdi: 4917
    ]

    public static func platformID(for canonicalID: CanonicalSystemID) -> Int? {
        byCanonicalID[canonicalID]
    }
}
