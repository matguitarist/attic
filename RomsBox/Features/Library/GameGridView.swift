import SwiftUI
import SwiftData
import RomsBoxPersistence

struct GameGridView: View {
    @Query private var games: [Game]
    @Binding var selectedGame: Game?
    private let sortOrder: GameSortOrder

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)]

    init(selection: LibrarySelection, searchText: String, sortOrder: GameSortOrder, selectedGame: Binding<Game?>) {
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
                        GameCoverCell(game: game, isSelected: game.persistentModelID == selectedGame?.persistentModelID)
                            .onTapGesture { selectedGame = game }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
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
