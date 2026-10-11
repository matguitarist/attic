import Foundation
import SwiftData
import RomsBoxModels

@Model
public final class GameSystem {
    /// Natural key: one row per canonical system, aggregating games scanned
    /// from whichever ROMs root(s) contain a matching system folder.
    @Attribute(.unique) public var canonicalID: String
    public var displayName: String
    /// The most recently scanned ROMs root that produced this system. If a
    /// system is scanned from multiple roots over time, this reflects the
    /// latest one — fine for MVP since `Game.romAbsolutePath` is
    /// self-contained and doesn't depend on this field at read time.
    public var romsRootPath: String
    public var libraryFormatRaw: String
    private var defaultLaunchTargetData: Data?
    /// Denormalized so the sidebar can show per-system counts without
    /// faulting in every `Game` row through the `games` relationship just
    /// to call `.count` on it. Kept current by `LibraryStore.upsertSystem`,
    /// and backfilled for stores created before it existed by
    /// `LibraryStore.refreshGameCounts()`.
    public var gameCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Game.system)
    public var games: [Game] = []

    public init(
        canonicalID: CanonicalSystemID,
        displayName: String,
        romsRootURL: URL,
        libraryFormat: LibraryFormat,
        defaultLaunchTarget: LaunchTargetReference? = nil
    ) {
        self.canonicalID = canonicalID.rawValue
        self.displayName = displayName
        self.romsRootPath = romsRootURL.path
        self.libraryFormatRaw = libraryFormat.rawValue
        self.defaultLaunchTargetData = defaultLaunchTarget.flatMap { try? JSONEncoder().encode($0) }
    }
}

extension GameSystem {
    public var systemID: CanonicalSystemID { CanonicalSystemID(canonicalID) }
    public var romsRootURL: URL { URL(fileURLWithPath: romsRootPath) }
    public var libraryFormat: LibraryFormat { LibraryFormat(rawValue: libraryFormatRaw) ?? .esde }

    public var defaultLaunchTarget: LaunchTargetReference? {
        get { defaultLaunchTargetData.flatMap { try? JSONDecoder().decode(LaunchTargetReference.self, from: $0) } }
        set { defaultLaunchTargetData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
