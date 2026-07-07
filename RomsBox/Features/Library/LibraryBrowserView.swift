import SwiftUI
import SwiftData
import RomsBoxPersistence

struct LibraryBrowserView: View {
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @State private var selection: LibrarySelection? = .allGames
    @State private var searchText = ""
    @State private var sortOrder: GameSortOrder = .title
    @State private var selectedGame: Game?
    @AppStorage("gridCellScale") private var cellScale: Double = 1.0

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(systems: systems, selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectionTitle)
                        .font(.largeTitle.bold())
                    Spacer()
                    ScrapeMissingButton(selection: selection ?? .allGames)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

                LibraryTopBar(searchText: $searchText, sortOrder: $sortOrder, cellScale: $cellScale)
                BatchScrapeStatusBar()
                Divider()
                GameGridView(
                    selection: selection ?? .allGames,
                    searchText: searchText,
                    sortOrder: sortOrder,
                    cellScale: CGFloat(cellScale),
                    selectedGame: $selectedGame
                )
            }
            // Content:detail defaults to roughly 2:1 (2/3 vs 1/3 of the pane).
            .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        } detail: {
            GameDetailView(game: selectedGame)
                // Capped so the detail/inspector pane doesn't silently
                // absorb all leftover window width on larger screens —
                // NavigationSplitView otherwise grows the trailing column
                // to fill any space beyond the sum of every column's ideal
                // width, which left detail far wider than the grid.
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        }
    }

    private var selectionTitle: String {
        switch selection ?? .allGames {
        case .allGames: "All Games"
        case .favorites: "Favorites"
        case .recentlyPlayed: "Recently Played"
        case .system(let canonicalID):
            systems.first { $0.systemID == canonicalID }?.displayName ?? canonicalID.rawValue
        }
    }
}
