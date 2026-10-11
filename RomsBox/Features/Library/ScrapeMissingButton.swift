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
            Section("Scrape \(missingCount) Missing From") {
                Button("ScreenScraper") {
                    scrapeCoordinator.scrapeAllMissing(games: games, source: .screenScraper(screenScraperCredentialsStore.credentials))
                }
                .disabled(!screenScraperCredentialsStore.isConfigured)

                Button("TheGamesDB") {
                    scrapeCoordinator.scrapeAllMissing(games: games, source: .theGamesDB(theGamesDBCredentialsStore.credentials))
                }
                .disabled(!theGamesDBCredentialsStore.isConfigured)
            }
        } label: {
            Label("Scrape Missing", systemImage: "photo.badge.arrow.down")
        }
        .disabled(missingCount == 0 || isRunning || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
        .help(missingCount == 0 ? "Every game in this list already has info" : "Scrape info for the \(missingCount) game(s) in this list missing it")
    }
}
