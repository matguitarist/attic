import Foundation
import SwiftData
import RomsBoxModels

/// Owns all writes to the SwiftData store so bulk scan operations never
/// block the main-actor `ModelContext` the UI's `@Query`s observe.
@ModelActor
public actor LibraryStore {

    public struct UpsertResult: Sendable, Equatable {
        public let gamesInserted: Int
        public let gamesUpdated: Int
        public let gamesRemoved: Int
    }

    /// Upserts one imported system and its games, keyed by
    /// (canonical system id, ROM relative path). Games present in a
    /// previous scan but absent from `data.games` are deleted, keeping
    /// rescans an accurate reflection of what's on disk.
    @discardableResult
    public func upsertSystem(_ data: ImportedSystemData, displayName: String) throws -> UpsertResult {
        let canonicalIDString = data.canonicalID.rawValue

        let systemDescriptor = FetchDescriptor<GameSystem>(
            predicate: #Predicate { $0.canonicalID == canonicalIDString }
        )
        let system: GameSystem
        if let existing = try modelContext.fetch(systemDescriptor).first {
            existing.displayName = displayName
            existing.romsRootPath = data.romsRootURL.path
            existing.libraryFormatRaw = data.libraryFormat.rawValue
            system = existing
        } else {
            system = GameSystem(
                canonicalID: data.canonicalID,
                displayName: displayName,
                romsRootURL: data.romsRootURL,
                libraryFormat: data.libraryFormat
            )
            modelContext.insert(system)
        }

        let gameDescriptor = FetchDescriptor<Game>(
            predicate: #Predicate { $0.systemCanonicalID == canonicalIDString }
        )
        var existingByPath = Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(gameDescriptor).map { ($0.romRelativePath, $0) }
        )

        var inserted = 0
        var updated = 0

        for record in data.games {
            if let existing = existingByPath.removeValue(forKey: record.romRelativePath) {
                existing.applyRescannedMetadata(record, romsRootURL: data.romsRootURL)
                updated += 1
            } else {
                let game = Game(
                    system: system,
                    systemCanonicalID: data.canonicalID,
                    romsRootURL: data.romsRootURL,
                    record: record
                )
                modelContext.insert(game)
                inserted += 1
            }
        }

        // Anything left is a ROM that was present in a previous scan but is
        // no longer on disk.
        for stale in existingByPath.values {
            modelContext.delete(stale)
        }
        let removed = existingByPath.count

        try modelContext.save()
        return UpsertResult(gamesInserted: inserted, gamesUpdated: updated, gamesRemoved: removed)
    }

    public func systemCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<GameSystem>())
    }

    public func gameCount(forSystem canonicalID: CanonicalSystemID) throws -> Int {
        let idString = canonicalID.rawValue
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.systemCanonicalID == idString })
        return try modelContext.fetchCount(descriptor)
    }

    public func totalGameCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Game>())
    }
}
