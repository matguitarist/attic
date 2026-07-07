import SwiftUI
import SwiftData
import RomsBoxPersistence

/// Bulk-scrapes every game missing a description within the current
/// sidebar selection — "per system" falls out naturally, since this is
/// scoped to whatever `selection` the sidebar currently has active
/// (a single system, Favorites, Recently Played, or all of it).
struct ScrapeMissingButton: View {
    @Query private var games: [Game]
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

    init(selection: LibrarySelection) {
        _games = Query(filter: GameGridView.selectionPredicate(selection))
    }

    private var missingCount: Int {
        games.filter { $0.gameDescription == nil }.count
    }

    private var isRunning: Bool {
        if case .running = scrapeCoordinator.batchState { return true }
        return false
    }

    var body: some View {
        Menu {
            Button("ScreenScraper") {
                scrapeCoordinator.scrapeAllMissing(games: games, source: .screenScraper(screenScraperCredentialsStore.credentials))
            }
            .disabled(!screenScraperCredentialsStore.isConfigured)

            Button("TheGamesDB") {
                scrapeCoordinator.scrapeAllMissing(games: games, source: .theGamesDB(theGamesDBCredentialsStore.credentials))
            }
            .disabled(!theGamesDBCredentialsStore.isConfigured)
        } label: {
            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Label("Scrape Missing (\(missingCount))", systemImage: "photo.stack")
            }
        }
        // Same manual Capsule/glassEffect treatment as the search field,
        // sort menu, and zoom slider (instead of .buttonStyle(.glass),
        // whose padding/corner radius don't match those) so every pill in
        // the top bar reads as one consistent family of controls.
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .disabled(missingCount == 0 || isRunning || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
        .help("Scrape missing info for every game in this list")
    }
}
