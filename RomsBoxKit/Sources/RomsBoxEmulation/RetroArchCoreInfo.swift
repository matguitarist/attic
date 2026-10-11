import Foundation
import RomsBoxModels

/// One installed RetroArch core, as described by its `.info` file.
public struct RetroArchCoreInfo: Sendable, Hashable, Identifiable {
    /// The core's filename without extension, e.g. "snes9x_libretro" —
    /// stable across RetroArch reinstalls/updates, used as the persisted
    /// identifier in `LaunchTargetReference.retroArchCore`.
    public let coreIdentifier: String
    public let displayName: String
    public let dylibURL: URL
    public let supportedExtensions: [String]
    /// The raw `systemid` value from the `.info` file, e.g. "mega_drive".
    public let systemID: String?
    public let canonicalSystemID: CanonicalSystemID?
    /// Every system this core runs, from its `.info` `database` list plus
    /// `systemid` — e.g. Genesis Plus GX → Genesis, Master System, Game
    /// Gear and Sega CD.
    public let systems: [CanonicalSystemID]

    public var id: String { coreIdentifier }

    public init(
        coreIdentifier: String,
        displayName: String,
        dylibURL: URL,
        supportedExtensions: [String],
        systemID: String?,
        canonicalSystemID: CanonicalSystemID?,
        systems: [CanonicalSystemID]? = nil
    ) {
        self.coreIdentifier = coreIdentifier
        self.displayName = displayName
        self.dylibURL = dylibURL
        self.supportedExtensions = supportedExtensions
        self.systemID = systemID
        self.canonicalSystemID = canonicalSystemID
        self.systems = systems ?? canonicalSystemID.map { [$0] } ?? []
    }
}
