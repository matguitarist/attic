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
        try? await libraryStore.backfillDatesAdded()
    }

    func gameFiles() async -> [LibraryStore.GameFile] {
        (try? await libraryStore.gameFiles()) ?? []
    }

    func gameMedia() async -> [LibraryStore.GameMedia] {
        (try? await libraryStore.gameMedia()) ?? []
    }

    func applyImported(_ info: [String: LibraryStore.ImportedInfo], replacing: Bool) async -> Int {
        (try? await libraryStore.applyImported(info, replacing: replacing)) ?? 0
    }

    func applyRenames(_ renames: [LibraryStore.RenamedFile]) async {
        try? await libraryStore.applyRenames(renames)
    }

    func saveDATVerdicts(_ verdicts: [String: (verdict: String?, name: String?)]) async {
        try? await libraryStore.setDATVerdicts(verdicts)
    }

    /// Scans the ROMs folders: every system's, or only those of `only`.
    func scan(romsRootURLs: [URL], only: Set<CanonicalSystemID>? = nil) async {
        guard !romsRootURLs.isEmpty else { return }
        state = .scanning

        let scanner = self.scanner
        let result = await Task.detached(priority: .userInitiated) {
            // Vita games installed in Vita3K since the last scan, and
            // playlists for multi-disc games.
            Vita3KLibrary.addShortcuts(romsRoots: romsRootURLs)
            DiscPlaylists.createMissing(romsRoots: romsRootURLs)
            return scanner.scan(romsRootURLs: romsRootURLs, only: only)
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
        _ = try? await libraryStore.addMatchingGamesToCollections()

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
        func fetch(_ url: URL) -> @Sendable () async throws -> Data {
            {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return data
            }
        }
        // FinalBurn Neo's first (it has years and makers), then MAME's
        // names for the boards it doesn't run.
        let fbneo = await ArcadeNameIndex.load(cacheURL: arcadeNameCaches[0], fetchDAT: fetch(ArcadeNameIndex.datURL))
        let mame = await ArcadeNameIndex.load(cacheURL: arcadeNameCaches[1], fetchDAT: fetch(ArcadeNameIndex.mameNamesURL))
        guard let index = fbneo.map({ mame.map($0.adding) ?? $0 }) ?? mame else { return systems }
        return systems.map { isArcade($0) ? index.applying(to: $0) : $0 }
    }

    /// FinalBurn Neo's names, then MAME's.
    nonisolated static var arcadeNameCaches: [URL] {
        ["ArcadeNames.json", "ArcadeNamesMAME.json"].map {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Attic/\($0)")
        }
    }
}
