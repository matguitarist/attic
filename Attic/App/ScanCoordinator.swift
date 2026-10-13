import Foundation
import Observation
import AtticModels
import AtticPersistence
import AtticLibraryScanning
import AtticEmulation

/// Bridges `LibraryScanner`'s output into `LibraryStore`. Lives in the app
/// layer specifically so `AtticLibraryScanning` stays independent of
/// `AtticPersistence` and independently testable against fixtures.
@Observable
@MainActor
final class ScanCoordinator {
    enum State: Equatable {
        case idle
        case scanning
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastScanSummary: String?

    private let libraryStore: LibraryStore
    private let scanner: LibraryScanner

    init(libraryStore: LibraryStore, scanner: LibraryScanner = LibraryScanner()) {
        self.libraryStore = libraryStore
        self.scanner = scanner
    }

    /// Backfills `GameSystem.gameCount` for libraries scanned before that
    /// field existed — see `LibraryStore.refreshGameCounts()`.
    func refreshGameCounts() async {
        try? await libraryStore.refreshGameCounts()
    }

    func gameFiles() async -> [LibraryStore.GameFile] {
        (try? await libraryStore.gameFiles()) ?? []
    }

    func saveDATVerdicts(_ verdicts: [String: (verdict: String?, name: String?)]) async {
        try? await libraryStore.setDATVerdicts(verdicts)
    }

    func scan(romsRootURLs: [URL]) async {
        guard !romsRootURLs.isEmpty else { return }
        state = .scanning

        let scanner = self.scanner
        let result = await Task.detached(priority: .userInitiated) {
            // Vita games installed in Vita3K since the last scan, and
            // playlists for multi-disc games.
            Vita3KLibrary.addShortcuts(romsRoots: romsRootURLs)
            DiscPlaylists.createMissing(romsRoots: romsRootURLs)
            return scanner.scan(romsRootURLs: romsRootURLs)
        }.value
        // Systems the user removed stay out until added back.
        let systems = await Self.withArcadeNames(result.systems.filter { !RemovedSystems.contains($0.canonicalID) })

        var systemsSaved = 0
        var gamesInserted = 0
        var gamesUpdated = 0
        var gamesRemoved = 0

        for systemData in systems {
            let displayName = SystemTaxonomy.definition(for: systemData.canonicalID)?.displayName
                ?? systemData.canonicalID.rawValue
            do {
                let upsertResult = try await libraryStore.upsertSystem(systemData, displayName: displayName)
                systemsSaved += 1
                gamesInserted += upsertResult.gamesInserted
                gamesUpdated += upsertResult.gamesUpdated
                gamesRemoved += upsertResult.gamesRemoved
            } catch {
                state = .failed(String(localized: "Failed to save \(displayName): \(error.localizedDescription)"))
                return
            }
        }

        // Collections that keep themselves up to date pick up new games.
        try? await libraryStore.addMatchingGamesToCollections()

        var summary = "\(systemsSaved) system(s) scanned — \(gamesInserted) new, \(gamesUpdated) updated"
        if gamesRemoved > 0 {
            summary += ", \(gamesRemoved) removed"
        }
        if !result.issues.isEmpty {
            summary += " (\(result.issues.count) folder(s) skipped)"
        }
        lastScanSummary = summary
        state = .idle
    }

    /// Arcade games are files named after their romset (`mslug.zip`); this
    /// swaps in their real titles from FinalBurn Neo's DAT unless a
    /// gamelist.xml already named them. Only fetched when the library has
    /// arcade systems, and a failed fetch just leaves the names as they are.
    nonisolated private static func withArcadeNames(_ systems: [ImportedSystemData]) async -> [ImportedSystemData] {
        let isArcade = { (system: ImportedSystemData) in
            SystemTaxonomy.definition(for: system.canonicalID)?.category == .arcade
        }
        guard systems.contains(where: isArcade) else { return systems }
        let index = await ArcadeNameIndex.load(cacheURL: arcadeNamesCacheURL) {
            let (data, response) = try await URLSession.shared.data(from: ArcadeNameIndex.datURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
        guard let index else { return systems }
        return systems.map { isArcade($0) ? index.applying(to: $0) : $0 }
    }

    nonisolated private static var arcadeNamesCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Attic/ArcadeNames.json")
    }
}
