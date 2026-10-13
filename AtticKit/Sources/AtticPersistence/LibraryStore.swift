import Foundation
import SwiftData
import AtticModels

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
    /// rescans in sync with what the importer reports. Note this is *not*
    /// the same as "still present on disk": a game listed in gamelist.xml
    /// is trusted even if its ROM file is temporarily missing (e.g. an
    /// unmounted external drive) — only the unscraped/bare-file fallback
    /// path (ES-DE games with no gamelist.xml entry) is driven by live
    /// filesystem presence. This avoids silently deleting curated metadata
    /// and user state (favorite, play history) over a transient I/O hiccup.
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

        var unmatched: [ImportedGameRecord] = []
        for record in data.games {
            if let existing = existingByPath.removeValue(forKey: record.romRelativePath) {
                existing.applyRescannedMetadata(record, romsRootURL: data.romsRootURL)
                updated += 1
            } else {
                unmatched.append(record)
            }
        }

        // A game whose file was swapped for one of the same name (compressed
        // to a .chd or .zip, or back) stays the same game: its favorite,
        // play history and collections carry over. Only when the name
        // leaves no doubt which game it was.
        var renamedKeys: [String: String] = [:]
        let newStems = Dictionary(grouping: unmatched) { Self.stem($0.romRelativePath) }
        let oldStems = Dictionary(grouping: existingByPath.values) { Self.stem($0.romRelativePath) }
        for record in unmatched {
            let stem = Self.stem(record.romRelativePath)
            if newStems[stem]?.count == 1, let old = oldStems[stem], old.count == 1, let existing = old.first,
               existingByPath.removeValue(forKey: existing.romRelativePath) != nil {
                let oldKey = existing.collectionKey
                existing.romRelativePath = record.romRelativePath
                renamedKeys[oldKey] = existing.collectionKey
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

        // Games taken out of a collection by hand stay out under their new
        // file name.
        if !renamedKeys.isEmpty {
            for collection in try modelContext.fetch(FetchDescriptor<GameCollection>()) {
                let keys = collection.excludedGameKeys.map { renamedKeys[$0] ?? $0 }
                if keys != collection.excludedGameKeys { collection.excludedGameKeys = keys }
            }
        }

        // Anything left is a ROM that was present in a previous scan but is
        // no longer on disk.
        for stale in existingByPath.values {
            modelContext.delete(stale)
        }
        let removed = existingByPath.count
        system.gameCount = inserted + updated

        try modelContext.save()
        return UpsertResult(gamesInserted: inserted, gamesUpdated: updated, gamesRemoved: removed)
    }

    /// Recomputes every system's stored `gameCount` from the actual rows.
    /// Only really needed once, for libraries scanned before the field
    /// existed (they'd otherwise show 0 until the next rescan), but cheap
    /// enough — one COUNT query per system — to just run at launch.
    public func refreshGameCounts() throws {
        for system in try modelContext.fetch(FetchDescriptor<GameSystem>()) {
            let idString = system.canonicalID
            let count = try modelContext.fetchCount(FetchDescriptor<Game>(predicate: #Predicate { $0.systemCanonicalID == idString }))
            if system.gameCount != count {
                system.gameCount = count
            }
        }
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    /// Adds to each collection that keeps itself up to date the games its
    /// search now finds (after a scan brought new ones). Returns how many.
    @discardableResult
    public func addMatchingGamesToCollections() throws -> Int {
        let collections = try modelContext.fetch(FetchDescriptor<GameCollection>(predicate: #Predicate { $0.addsMatchingGames }))
        guard !collections.isEmpty else { return 0 }
        let games = try modelContext.fetch(FetchDescriptor<Game>())
        var added = 0
        for collection in collections where !collection.search.isEmpty {
            let members = Set(collection.games.map(\.persistentModelID))
            for game in games where !members.contains(game.persistentModelID) && collection.searchMatches(game) {
                collection.games.append(game)
                added += 1
            }
        }
        if modelContext.hasChanges { try modelContext.save() }
        return added
    }

    /// A game's file, for checking it against a DAT.
    public struct GameFile: Sendable {
        public let path: String
        public let system: CanonicalSystemID
        public let title: String
    }

    public func gameFiles() throws -> [GameFile] {
        try modelContext.fetch(FetchDescriptor<Game>()).map {
            GameFile(path: $0.romAbsolutePath, system: CanonicalSystemID($0.systemCanonicalID), title: $0.title)
        }
    }

    /// What a DAT said of each game, by path: its verdict and the DAT's
    /// name for it (nils when there was no DAT to check it against).
    public func setDATVerdicts(_ verdicts: [String: (verdict: String?, name: String?)]) throws {
        for game in try modelContext.fetch(FetchDescriptor<Game>()) {
            guard let result = verdicts[game.romAbsolutePath] else { continue }
            if game.datVerdict != result.verdict { game.datVerdict = result.verdict }
            if game.datName != result.name { game.datName = result.name }
        }
        if modelContext.hasChanges { try modelContext.save() }
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

    /// A game's path without its extension, for matching swapped files.
    static func stem(_ path: String) -> String {
        (path as NSString).deletingPathExtension.lowercased()
    }
}
