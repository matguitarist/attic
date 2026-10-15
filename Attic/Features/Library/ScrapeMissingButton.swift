import SwiftUI
import SwiftData
import AtticPersistence

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
        let logos = LogoIndex()
        return games.filter { ScrapeCoordinator.lacksInfo($0, from: nil, logos: logos) }.count
    }

    private var isRunning: Bool {
        if case .running = scrapeCoordinator.batchState { return true }
        return false
    }

    var body: some View {
        let missingCount = missingCount
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
        scrapeCoordinator.scrape(selection, from: source, force: force, in: modelContext)
    }
}

/// The same choices as `ScrapeSelectionMenu`, from a plain button. Inside
/// a grouped Form a Menu is always drawn as a pop-up row; this one sits
/// among buttons and should look and hover like them.
struct ScrapeSelectionButton: View {
    let title: LocalizedStringKey
    let selection: LibrarySelection

    @Environment(\.modelContext) private var modelContext
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

    var body: some View {
        Button(title) { showMenu() }
            .disabled(isRunning || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
    }

    private var isRunning: Bool {
        if case .running = scrapeCoordinator.batchState { return true }
        return false
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: String(localized: "Games Missing Info")))
        addSources(to: menu, force: false)
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: String(localized: "All Games, Replacing Existing Info")))
        addSources(to: menu, force: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func addSources(to menu: NSMenu, force: Bool) {
        let screenScraper = screenScraperCredentialsStore
        let theGamesDB = theGamesDBCredentialsStore
        menu.addItem(ClosureMenuItem("ScreenScraper", enabled: screenScraper.isConfigured) {
            start(.screenScraper(screenScraper.credentials), force: force)
        })
        menu.addItem(ClosureMenuItem("TheGamesDB", enabled: theGamesDB.isConfigured) {
            start(.theGamesDB(theGamesDB.credentials), force: force)
        })
    }

    private func start(_ source: ScrapeCoordinator.ScraperSource, force: Bool) {
        scrapeCoordinator.scrape(selection, from: source, force: force, in: modelContext)
    }
}

/// An AppKit menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

extension ScrapeCoordinator {
    /// Scrapes every game in `selection`: only those missing info, or all
    /// of them replacing what they have (`force`).
    func scrape(_ selection: LibrarySelection, from source: ScraperSource, force: Bool, in context: ModelContext) {
        let descriptor = FetchDescriptor(predicate: GameGridView.selectionPredicate(selection), sortBy: [SortDescriptor(\Game.sortTitle)])
        guard let games = try? context.fetch(descriptor), !games.isEmpty else { return }
        if force {
            scrape(games: games, from: source, force: true)
        } else {
            scrapeAllMissing(games: games, source: source)
        }
    }
}
