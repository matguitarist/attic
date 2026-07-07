import RomsBoxModels

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
