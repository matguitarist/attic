import Foundation

/// What a system's games came on, which its `physicalmedia` pictures show
/// (ES-DE's name for the folder): a cartridge, a disc, an arcade board…
public enum PhysicalMedium: String, Sendable, CaseIterable {
    case cartridge, disc, card, disk, cassette, board

    /// The medium of `system`'s games (a hack folder's, its system's), nil
    /// for those that never had one (Steam, PICO-8, game engines).
    public static func of(_ system: CanonicalSystemID) -> PhysicalMedium? {
        let system = system.baseSystem
        if let medium = media[system.rawValue] { return medium }
        if noMedium.contains(system.rawValue) { return nil }
        return switch SystemTaxonomy.definition(for: system)?.category {
        case .arcade?: .board
        case .computer?: .disk
        default: .cartridge
        }
    }

    private static let media: [String: PhysicalMedium] = [
        // Discs: CDs, DVDs, GD-ROMs, UMDs and Blu-rays.
        "psx": .disc, "ps2": .disc, "ps3": .disc, "ps4": .disc, "psp": .disc,
        "segacd": .disc, "saturn": .disc, "dreamcast": .disc, "pcenginecd": .disc, "pcfx": .disc,
        "threedo": .disc, "cdi": .disc, "gamecube": .disc, "wii": .disc, "wiiu": .disc, "xbox": .disc,
        "neogeocd": .disc,
        // Arcade boards that read GD-ROMs.
        "naomigd": .disc,
        // HuCards and the Vita's cards.
        "pcengine": .card, "supergrafx": .card, "psvita": .card,
        // Floppies on consoles.
        "fds": .disk, "n64dd": .disk,
        // Computers that took cartridges or tapes.
        "msx": .cartridge, "vic20": .cartridge, "atari800": .cartridge,
        "zxspectrum": .cassette, "zx81": .cassette, "plus4": .cassette,
    ]

    private static let noMedium: Set<String> = [
        "steam", "scummvm", "doom", "quake", "easyrpg", "pico8", "tic80", "wasm4", "arduboy", "gameandwatch"
    ]
}
