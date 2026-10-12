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
        .help(missingCount == 0 ? String(localized: "Every game in this list already has info") : String(localized: "Scrape info for the \(missingCount) games in this list missing it"))
    }
}

/// "Scrape This System" / "Scrape This Collection" in the sidebar's
/// context menu: games missing info, or every game replacing what it has.
/// Fetches the games only when chosen, so the sidebar doesn't keep a query
/// per row.
struct ScrapeSelectionMenu: View {
    let title: LocalizedStringKey
    let selection: LibrarySelection

    @Environment(\.modelContext) private var modelContext
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

    var body: some View {
        Menu(title) {
            Section("Games Missing Info") {
                sourceButtons(force: false)
            }
            Section("All Games, Replacing Existing Info") {
                sourceButtons(force: true)
            }
        }
        .disabled(isRunning || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
    }

    private var isRunning: Bool {
        if case .running = scrapeCoordinator.batchState { return true }
        return false
    }

    @ViewBuilder
    private func sourceButtons(force: Bool) -> some View {
        Button("ScreenScraper") {
            start(.screenScraper(screenScraperCredentialsStore.credentials), force: force)
        }
        .disabled(!screenScraperCredentialsStore.isConfigured)

        Button("TheGamesDB") {
            start(.theGamesDB(theGamesDBCredentialsStore.credentials), force: force)
        }
        .disabled(!theGamesDBCredentialsStore.isConfigured)
    }

    private func start(_ source: ScrapeCoordinator.ScraperSource, force: Bool) {
        let descriptor = FetchDescriptor(predicate: GameGridView.selectionPredicate(selection), sortBy: [SortDescriptor(\Game.sortTitle)])
        guard let games = try? modelContext.fetch(descriptor), !games.isEmpty else { return }
        if force {
            scrapeCoordinator.scrape(games: games, from: source, force: true)
        } else {
            scrapeCoordinator.scrapeAllMissing(games: games, source: source)
        }
    }
}
