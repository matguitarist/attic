import Foundation
import Observation
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxLibraryScanning

/// Bridges `LibraryScanner`'s output into `LibraryStore`. Lives in the app
/// layer specifically so `RomsBoxLibraryScanning` stays independent of
/// `RomsBoxPersistence` and independently testable against fixtures.
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

    func scan(romsRootURLs: [URL]) async {
        guard !romsRootURLs.isEmpty else { return }
        state = .scanning

        let scanner = self.scanner
        let result = await Task.detached(priority: .userInitiated) {
            scanner.scan(romsRootURLs: romsRootURLs)
        }.value

        var systemsSaved = 0
        var gamesInserted = 0
        var gamesUpdated = 0
        var gamesRemoved = 0

        for systemData in result.systems {
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
}
