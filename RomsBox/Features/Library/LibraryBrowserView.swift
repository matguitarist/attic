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
        // Two columns, not three — the title/search/sort header needs to
        // span the full width above *both* the grid and the detail panel,
        // which a three-column NavigationSplitView (sidebar/content/detail)
        // can't express since each column owns its own top-to-bottom
        // content independently. Grid and detail are instead a manual
        // resizable split living below one shared header, so they start at
        // exactly the same height.
        NavigationSplitView {
            LibrarySidebarView(systems: systems, selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                header
                LibraryTopBar(searchText: $searchText, sortOrder: $sortOrder, cellScale: $cellScale)
                BatchScrapeStatusBar()
                Divider()
                ResizableHSplit(initialTrailingWidth: 320, minTrailingWidth: 260, maxTrailingWidth: 480) {
                    GameGridView(
                        selection: selection ?? .allGames,
                        searchText: searchText,
                        sortOrder: sortOrder,
                        cellScale: CGFloat(cellScale),
                        selectedGame: $selectedGame
                    )
                } trailing: {
                    GameDetailView(game: selectedGame)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selectionTitle)
                .font(.largeTitle.bold())
            Spacer()
            ScrapeMissingButton(selection: selection ?? .allGames)
        }
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 2)
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
