import SwiftUI
import SwiftData
import RomsBoxPersistence

struct GameGridView: View {
    @Query private var games: [Game]
    @Binding var selectedGame: Game?
    private let sortOrder: GameSortOrder

    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

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
                            .onTapGesture { selectedGame = game }
                            .contextMenu { contextMenuContent(for: game) }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private func contextMenuContent(for game: Game) -> some View {
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
