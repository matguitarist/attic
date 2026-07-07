import SwiftUI
import SwiftData
import RomsBoxPersistence

struct LibraryBrowserView: View {
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @State private var selection: LibrarySelection? = .allGames
    @State private var searchText = ""
    @State private var sortOrder: GameSortOrder = .title
    @State private var selectedGame: Game?

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(systems: systems, selection: $selection)
        } content: {
            GameGridView(
                selection: selection ?? .allGames,
                searchText: searchText,
                sortOrder: sortOrder,
                selectedGame: $selectedGame
            )
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(GameSortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } detail: {
            GameDetailView(game: selectedGame)
        }
    }
}
