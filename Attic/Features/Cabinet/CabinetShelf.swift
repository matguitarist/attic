import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// One section's games in the theme's layout, and the focus moving
/// through them. Owns the section's query, so switching sections swaps
/// the whole shelf.
///
/// Each layout moves along its own axis — the carousel left and right,
/// the wheel and list up and down, the grid both — and the other directions step
/// through sections, so a pad without (or with awkward) shoulder buttons
/// can still get everywhere.
struct CabinetShelf: View {
    @Query private var queriedGames: [Game]
    /// Collections follow the library window's collection order.
    private let sortsBySystem: Bool
    /// Recently Added shows only the newest.
    private let limit: Bool
    @AppStorage("collectionSortOrder") private var collectionSortOrder = GameSortOrder.systemThenRelease

    private var games: [Game] {
        if limit { return Array(queriedGames.prefix(GameGridView.recentlyAddedCount)) }
        return sortsBySystem && collectionSortOrder == .systemThenRelease ? GameGridView.bySystemThenRelease(queriedGames) : queriedGames
    }
    let event: CabinetEvent?
    @Binding var focusedGame: Game?
    @Binding var gameCount: Int
    let onSectionStep: (Int) -> Void

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(\.cabinetTheme) private var installed
    /// The grid's, for moving up and down a row.
    @State private var columns = 1

    init(selection: LibrarySelection, event: CabinetEvent?, focusedGame: Binding<Game?>, gameCount: Binding<Int>,
         onSectionStep: @escaping (Int) -> Void) {
        let sort: [SortDescriptor<Game>] = switch selection {
        case .recentlyPlayed: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
        case .recentlyAdded: [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.sortTitle)]
        default: [SortDescriptor(\.sortTitle)]
        }
        _queriedGames = Query(filter: GameGridView.selectionPredicate(selection), sort: sort)
        if case .collection = selection { sortsBySystem = true } else { sortsBySystem = false }
        limit = selection == .recentlyAdded
        self.event = event
        _focusedGame = focusedGame
        _gameCount = gameCount
        self.onSectionStep = onSectionStep
    }

    var body: some View {
        let games = games
        Group {
            if games.isEmpty {
                ContentUnavailableView {
                    Label("No Games Here", systemImage: "gamecontroller")
                } description: {
                    Text("Switch sections with LB / RB.")
                }
                .foregroundStyle(installed.theme.palette.secondaryText.color)
                .frame(maxHeight: .infinity)
            } else {
                let shelf = CabinetShelfContent(games: games, focusedID: focusedGame?.persistentModelID,
                                                onFocus: { focus($0) }, onPlay: play)
                switch installed.theme.layout {
                case .carousel: CabinetCarouselLayout(shelf: shelf)
                case .grid: CabinetGridLayout(shelf: shelf, columns: $columns)
                case .wheel: CabinetWheelLayout(shelf: shelf)
                case .list: CabinetListLayout(shelf: shelf)
                }
            }
        }
        .onAppear { focus(games.first) }
        .onChange(of: games.count, initial: true) { _, count in gameCount = count }
        .onChange(of: event) { _, newEvent in
            guard let newEvent else { return }
            handle(newEvent.command)
        }
    }

    private func handle(_ command: CabinetEvent.Command) {
        switch command {
        case .move(let direction):
            move(direction)
        case .activate:
            if let focusedGame { play(focusedGame) }
        case .toggleFavorite:
            if let focusedGame {
                focusedGame.favorite.toggle()
                try? focusedGame.modelContext?.save()
            }
        case .previousSection, .nextSection, .back, .menu:
            break
        }
    }

    private func move(_ direction: GridMoveDirection) {
        let games = games
        let index = focusedGame.flatMap { focused in games.firstIndex { $0.persistentModelID == focused.persistentModelID } }
        switch (installed.theme.layout, direction) {
        case (.carousel, .left), (.wheel, .up), (.list, .up): focus(games[safe: (index ?? 0) - 1])
        case (.carousel, .right), (.wheel, .down), (.list, .down): focus(games[safe: (index ?? 0) + 1])
        case (.carousel, .up), (.wheel, .left), (.list, .left): onSectionStep(-1)
        case (.carousel, .down), (.wheel, .right), (.list, .right): onSectionStep(1)
        case (.grid, _):
            let target = GridNavigation.index(movingFrom: index, direction: direction, itemCount: games.count, columns: columns)
            focus(target.map { games[$0] })
        }
    }

    private func focus(_ game: Game?) {
        guard let game else { return }
        focusedGame = game
    }

    private func play(_ game: Game) {
        focus(game)
        launchCoordinator.play(game: game, retroArchStore: retroArchStore)
    }
}

/// What every layout gets: the games, which one has focus, and what
/// clicking does.
struct CabinetShelfContent {
    let games: [Game]
    let focusedID: PersistentIdentifier?
    let onFocus: (Game) -> Void
    let onPlay: (Game) -> Void

    var focusedGame: Game? {
        games.first { $0.persistentModelID == focusedID }
    }

    func isFocused(_ game: Game) -> Bool {
        game.persistentModelID == focusedID
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
