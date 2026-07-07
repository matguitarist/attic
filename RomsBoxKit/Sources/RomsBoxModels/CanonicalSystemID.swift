/// A stable, internal identifier for a game system (e.g. "snes"), independent
/// of any particular library convention's own short-name for that system.
///
/// Batocera/RetroBat and ES-DE sometimes disagree on short names for the same
/// system (e.g. Genesis/Mega Drive is `megadrive` in Batocera, `genesis` in
/// ES-DE) — `CanonicalSystemID` is the one vocabulary everything above the
/// importer layer is written against. See `SystemTaxonomy` for the alias table.
public struct CanonicalSystemID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CanonicalSystemID: CustomStringConvertible {
    public var description: String { rawValue }
}

extension CanonicalSystemID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public extension CanonicalSystemID {
    static let nes = CanonicalSystemID("nes")
    static let snes = CanonicalSystemID("snes")
    static let genesis = CanonicalSystemID("genesis")
    static let psx = CanonicalSystemID("psx")
    static let gba = CanonicalSystemID("gba")

    // Sega
    static let mastersystem = CanonicalSystemID("mastersystem")
    static let gamegear = CanonicalSystemID("gamegear")
    static let segacd = CanonicalSystemID("segacd")
    static let saturn = CanonicalSystemID("saturn")
    static let dreamcast = CanonicalSystemID("dreamcast")
    static let sega32x = CanonicalSystemID("sega32x")

    // Atari
    static let atari2600 = CanonicalSystemID("atari2600")
    static let atari5200 = CanonicalSystemID("atari5200")
    static let atari7800 = CanonicalSystemID("atari7800")
    static let atarilynx = CanonicalSystemID("atarilynx")
    static let atarijaguar = CanonicalSystemID("atarijaguar")

    // NEC
    static let pcengine = CanonicalSystemID("pcengine")
    static let pcenginecd = CanonicalSystemID("pcenginecd")
    static let pcfx = CanonicalSystemID("pcfx")
    static let supergrafx = CanonicalSystemID("supergrafx")

    // Other
    static let threedo = CanonicalSystemID("3do")
    static let cdi = CanonicalSystemID("cdi")
}
