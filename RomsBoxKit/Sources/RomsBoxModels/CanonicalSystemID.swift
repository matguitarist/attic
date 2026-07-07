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
}
