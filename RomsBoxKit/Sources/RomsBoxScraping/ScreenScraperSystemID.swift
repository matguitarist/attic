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
        .gba: 12
    ]

    public static func systemeID(for canonicalID: CanonicalSystemID) -> Int? {
        byCanonicalID[canonicalID]
    }
}
