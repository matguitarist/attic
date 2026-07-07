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
        .gba: 5
    ]

    public static func platformID(for canonicalID: CanonicalSystemID) -> Int? {
        byCanonicalID[canonicalID]
    }
}
