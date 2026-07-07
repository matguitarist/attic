import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxEmulation

struct GameGridView: View {
    @Query private var games: [Game]
    @Binding var selectedGame: Game?
    private let sortOrder: GameSortOrder

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore
    @Query(sort: \EmulatorProfile.name) private var customEmulatorProfiles: [EmulatorProfile]

    private let cellScale: CGFloat

    // Fixed (not ranged) min==max width so every column — and therefore
    // every row — lines up identically regardless of window width; the grid
    // just fits however many equal-width columns fit. Scaled live by the
    // zoom slider rather than fixed at one size.
    static let baseCellWidth: CGFloat = 160
    private var cellWidth: CGFloat { Self.baseCellWidth * cellScale }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth), spacing: 20)] }

    init(selection: LibrarySelection, searchText: String, sortOrder: GameSortOrder, cellScale: CGFloat, selectedGame: Binding<Game?>) {
        self.cellScale = cellScale
        // Recently Played always shows most-recent-first, regardless of the
        // toolbar's sort picker — that's the one thing that view is for.
        let effectiveSortOrder: GameSortOrder = selection == .recentlyPlayed ? .lastPlayed : sortOrder

        // `Bool` isn't `Comparable`, so SwiftData's SortDescriptor can't sort
        // by `favorite` directly — fetch title-sorted and, for
        // `.favoriteFirst`, stably reorder in memory instead.
        _games = Query(
            filter: Self.predicate(selection: selection, searchText: searchText),
            sort: Self.sortDescriptors(for: effectiveSortOrder)
        )
        _selectedGame = selectedGame
        self.sortOrder = effectiveSortOrder
    }

    private var displayedGames: [Game] {
        guard sortOrder == .favoriteFirst else { return games }
        return games.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.favorite != rhs.element.favorite {
                    return lhs.element.favorite
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var body: some View {
        ScrollView {
            if games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text("No games match this selection.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(displayedGames) { game in
                        GameCoverCell(game: game, isSelected: game.persistentModelID == selectedGame?.persistentModelID, width: cellWidth)
                            // Both gestures attached together let SwiftUI
                            // disambiguate by tap count itself (waiting
                            // briefly after one tap to see if a second
                            // arrives) rather than needing to do that by hand.
                            .onTapGesture(count: 2) { play(game) }
                            .onTapGesture(count: 1) { selectedGame = game }
                            .contextMenu { contextMenuContent(for: game) }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
    }

    private func play(_ game: Game) {
        selectedGame = game
        launchCoordinator.play(game: game, retroArchStore: retroArchStore)
    }

    @ViewBuilder
    private func contextMenuContent(for game: Game) -> some View {
        let target = resolvedTarget(for: game)
        let isRunningThisGame = launchCoordinator.state == .running(gameID: game.persistentModelID)
        let isBusy = launchCoordinator.state == .launching || isRunningThisGame

        Button(isRunningThisGame ? "Running…" : "Play") {
            play(game)
        }
        .disabled(target == nil || isBusy)

        launchWithMenu(for: game)

        Divider()

        Button(game.favorite ? "Remove from Favorites" : "Add to Favorites") {
            game.favorite.toggle()
            try? game.modelContext?.save()
        }

        Divider()

        Menu("Scrape Info") {
            Button("ScreenScraper") {
                Task { await scrapeCoordinator.scrapeUsingScreenScraper(game: game, credentials: screenScraperCredentialsStore.credentials) }
            }
            .disabled(!screenScraperCredentialsStore.isConfigured)

            Button("TheGamesDB") {
                Task { await scrapeCoordinator.scrapeUsingTheGamesDB(game: game, credentials: theGamesDBCredentialsStore.credentials) }
            }
            .disabled(!theGamesDBCredentialsStore.isConfigured)
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.romAbsoluteURL])
        }
    }

    @ViewBuilder
    private func launchWithMenu(for game: Game) -> some View {
        Menu("Launch With") {
            if game.launchOverride != nil {
                Button("Use System Default") {
                    game.launchOverride = nil
                    try? game.modelContext?.save()
                }
                Divider()
            }

            if let systemID = game.system?.systemID {
                let cores = retroArchStore.cores(for: systemID)
                if !cores.isEmpty {
                    Section("RetroArch Cores") {
                        ForEach(cores) { core in
                            Button(core.displayName) {
                                game.launchOverride = .retroArchCore(coreIdentifier: core.coreIdentifier)
                                try? game.modelContext?.save()
                            }
                        }
                    }
                }

                let matchingProfiles = customEmulatorProfiles.filter { $0.assignedSystemIDs.contains(systemID) }
                if !matchingProfiles.isEmpty {
                    Section("Custom Emulators") {
                        ForEach(matchingProfiles) { profile in
                            Button(profile.name) {
                                game.launchOverride = .emulatorProfile(id: profile.id)
                                try? game.modelContext?.save()
                            }
                        }
                    }
                }
            }
        }
    }

    private func resolvedTarget(for game: Game) -> LaunchTargetReference? {
        LaunchTargetResolution.resolve(gameOverride: game.launchOverride, systemDefault: game.system?.defaultLaunchTarget)
    }

    /// Games belonging to `selection` alone, ignoring the search box — used
    /// where an action should apply to "everything currently shown by the
    /// sidebar," like bulk-scraping, independent of whatever's typed in
    /// search at that moment.
    static func selectionPredicate(_ selection: LibrarySelection) -> Predicate<Game> {
        switch selection {
        case .allGames:
            return #Predicate<Game> { _ in true }
        case .favorites:
            return #Predicate<Game> { $0.favorite }
        case .recentlyPlayed:
            return #Predicate<Game> { $0.lastPlayedDate != nil }
        case .system(let canonicalID):
            let systemID = canonicalID.rawValue
            return #Predicate<Game> { $0.systemCanonicalID == systemID }
        }
    }

    private static func predicate(selection: LibrarySelection, searchText: String) -> Predicate<Game> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch selection {
        case .allGames:
            if query.isEmpty {
                return #Predicate<Game> { _ in true }
            }
            return #Predicate<Game> { $0.title.localizedStandardContains(query) }
        case .favorites:
            if query.isEmpty {
                return #Predicate<Game> { $0.favorite }
            }
            return #Predicate<Game> { $0.favorite && $0.title.localizedStandardContains(query) }
        case .recentlyPlayed:
            if query.isEmpty {
                return #Predicate<Game> { $0.lastPlayedDate != nil }
            }
            return #Predicate<Game> { $0.lastPlayedDate != nil && $0.title.localizedStandardContains(query) }
        case .system(let canonicalID):
            let systemID = canonicalID.rawValue
            if query.isEmpty {
                return #Predicate<Game> { $0.systemCanonicalID == systemID }
            }
            return #Predicate<Game> { $0.systemCanonicalID == systemID && $0.title.localizedStandardContains(query) }
        }
    }

    private static func sortDescriptors(for order: GameSortOrder) -> [SortDescriptor<Game>] {
        switch order {
        case .title, .favoriteFirst:
            [SortDescriptor(\.sortTitle)]
        case .lastPlayed:
            [SortDescriptor(\.lastPlayedDate, order: .reverse)]
        }
    }
}
