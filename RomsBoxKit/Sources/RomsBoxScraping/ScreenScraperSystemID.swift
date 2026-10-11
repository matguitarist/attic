import RomsBoxModels

/// ScreenScraper's own numeric platform id ("systemeid"), which has no
/// relation to Batocera/ES-DE short-names or RetroArch `.info` `systemid`
/// values — a fourth, independent vocabulary alongside the three already
/// reconciled in `SystemTaxonomy`. Confirmed against ScreenScraper's public
/// system listing pages (e.g. `systemeinfos.php?plateforme=3` for NES).
public enum ScreenScraperSystemID {
    private static let byCanonicalID: [CanonicalSystemID: Int] = [
        .nes: 3,
        .snes: 4,
        .genesis: 1,
        .psx: 57,
        .gba: 12,
        .mastersystem: 2,
        .gamegear: 21,
        .segacd: 20,
        .saturn: 22,
        .dreamcast: 23,
        .sega32x: 19,
        .atari2600: 26,
        .atari5200: 40,
        .atari7800: 41,
        .atarilynx: 28,
        .atarijaguar: 27,
        .pcengine: 31,
        .virtualboy: 11,
        .neogeo: 142,
        .cps1: 6, .cps2: 7, .cps3: 8,
        .pcenginecd: 114,
        .pcfx: 72,
        .supergrafx: 105,
        .threedo: 29,
        .cdi: 133
    ]

    public static func systemeID(for canonicalID: CanonicalSystemID) -> Int? {
        byCanonicalID[canonicalID]
    }
}
