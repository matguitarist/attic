import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// One section's games in the theme's layout, and the focus moving
/// through them. Owns the section's query, so switching sections swaps
/// the whole shelf.
///
/// Each layout moves along its own axis — the carousel left and right,
/// the wheel and list up and down, the grid both — and the other
/// directions step through sections, so a pad without (or with awkward)
/// shoulder buttons can still get everywhere.
struct CabinetShelf: View {
    @Query private var queriedGames: [Game]
    /// Collections follow the library window's collection order.
    private let sortsBySystem: Bool
    /// Recently Added shows only the newest.
    private let limit: Bool
    private let isRecentlyPlayed: Bool
    @AppStorage("collectionSortOrder") private var collectionSortOrder = GameSortOrder.systemThenRelease

    /// What `games` is worked out from.
    private struct GamesKey: Equatable {
        let games: [Game]
        let collectionSortOrder: GameSortOrder
        let search: String
        let sort: CabinetSort
        let favoritesOnly: Bool
        let minPlayers: Int
        let genre: String
        /// Favorites only drops a game when it stops being one.
        let favorites: Int
        /// Most and Last Played reorder after a game is played.
        let plays: Int

        static func == (a: Self, b: Self) -> Bool {
            a.collectionSortOrder == b.collectionSortOrder && a.search == b.search && a.sort == b.sort
                && a.favoritesOnly == b.favoritesOnly && a.minPlayers == b.minPlayers && a.genre == b.genre
                && a.favorites == b.favorites && a.plays == b.plays && sameGames(a.games, b.games)
        }
    }

    /// The section's games in its own order, then searched, filtered and
    /// sorted (see `CabinetBrowse`) — once per change to any of those, not
    /// per redraw: a press redraws, and asks for them again besides.
    private var games: [Game] {
        let key = GamesKey(games: queriedGames, collectionSortOrder: collectionSortOrder, search: browse.appliedSearch,
                           sort: browse.sort, favoritesOnly: browse.favoritesOnly, minPlayers: browse.minPlayers,
                           genre: browse.genre, favorites: browse.favoritesOnly ? queriedGames.count(where: \.favorite) : 0,
                           plays: browse.sort == .mostPlayed || browse.sort == .lastPlayed ? queriedGames.reduce(0) { $0 + $1.playCount } : 0)
        return shown(key) { shownGames }
    }

    private var shownGames: [Game] {
        let ordered = if limit {
            Array(queriedGames.prefix(GameGridView.recentlyAddedCount))
        } else if sortsBySystem && collectionSortOrder == .systemThenRelease {
            GameGridView.bySystemThenRelease(queriedGames)
        } else {
            queriedGames
        }
        return browse.apply(to: ordered)
    }

    /// Whether the games run A to Z, for L2/R2's letter jumps.
    private var isTitleOrder: Bool {
        switch browse.sort {
        case .title: true
        case .section: !limit && !isRecentlyPlayed && !(sortsBySystem && collectionSortOrder == .systemThenRelease)
        case .year, .mostPlayed, .lastPlayed: false
        }
    }

    let event: CabinetEvent?
    @Binding var focusedGame: Game?
    @Binding var gameCount: Int
    /// Opens on a random game (Select on the systems).
    let startsRandom: Bool
    let onSectionStep: (Int) -> Void
    /// A: straight into the game.
    let onPlay: (Game) -> Void
    /// X: the game's page.
    let onDetails: (Game) -> Void
    /// Shows the letter (or position) a jump landed on.
    let onJump: (String) -> Void

    @Environment(CabinetBrowse.self) private var browse
    @Environment(\.cabinetTheme) private var installed
    @State private var shown = Memo<GamesKey, [Game]>()
    /// The grid's, for moving up and down a row.
    @State private var columns = 1

    /// `search`, when there is one, looks through every game rather than
    /// the section's: the database narrows by its first word, and
    /// `CabinetBrowse` checks the rest.
    init(selection: LibrarySelection, search: String = "", event: CabinetEvent?, focusedGame: Binding<Game?>, gameCount: Binding<Int>,
         startsRandom: Bool = false, onSectionStep: @escaping (Int) -> Void,
         onPlay: @escaping (Game) -> Void, onDetails: @escaping (Game) -> Void, onJump: @escaping (String) -> Void) {
        let sort: [SortDescriptor<Game>] = switch selection {
        case .recentlyPlayed: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
        case .recentlyAdded: [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.sortTitle)]
        default: [SortDescriptor(\.sortTitle)]
        }
        if let word = search.split(separator: " ").first.map(String.init) {
            _queriedGames = Query(filter: #Predicate<Game> { $0.title.localizedStandardContains(word) },
                                  sort: [SortDescriptor(\.sortTitle)])
            sortsBySystem = false
            limit = false
            isRecentlyPlayed = false
        } else {
            _queriedGames = Query(filter: GameGridView.selectionPredicate(selection), sort: sort)
            if case .collection = selection { sortsBySystem = true } else { sortsBySystem = false }
            limit = selection == .recentlyAdded
            isRecentlyPlayed = selection == .recentlyPlayed
        }
        self.event = event
        _focusedGame = focusedGame
        _gameCount = gameCount
        self.startsRandom = startsRandom
        self.onSectionStep = onSectionStep
        self.onPlay = onPlay
        self.onDetails = onDetails
        self.onJump = onJump
    }

    var body: some View {
        let games = games
        Group {
            if games.isEmpty && browse.isFiltered {
                ContentUnavailableView {
                    Label("No Games Match", systemImage: "magnifyingglass")
                } description: {
                    Text("Press B to clear the search and filters.")
                }
                .foregroundStyle(installed.theme.palette.secondaryText.color)
                .frame(maxHeight: .infinity)
            } else if games.isEmpty {
                ContentUnavailableView {
                    Label("No Games Here", systemImage: "gamecontroller")
                } description: {
                    Text("Switch sections with LB / RB.")
                }
                .foregroundStyle(installed.theme.palette.secondaryText.color)
                .frame(maxHeight: .infinity)
            } else {
                let shelf = CabinetShelfContent(games: games, focusedID: focusedGame?.persistentModelID,
                                                onFocus: { focus($0) }, onPlay: onPlay)
                switch installed.theme.layout {
                case .carousel: CabinetCarouselLayout(shelf: shelf)
                case .grid: CabinetGridLayout(shelf: shelf, columns: $columns)
                case .wheel: CabinetWheelLayout(shelf: shelf)
                case .list: CabinetListLayout(shelf: shelf)
                }
            }
        }
        .onAppear { focus(startsRandom ? games.randomElement() : games.first) }
        .onChange(of: games.count, initial: true) { _, count in gameCount = count }
        // A new search or filter keeps the focused game when it's still
        // there; a new order starts at the top.
        .onChange(of: "\(browse.appliedSearch)|\(browse.favoritesOnly)|\(browse.minPlayers)|\(browse.genre)") {
            let games = self.games
            if !games.contains(where: { $0.persistentModelID == focusedGame?.persistentModelID }) { focus(games.first) }
        }
        .onChange(of: browse.sort) { focus(self.games.first) }
        .onChange(of: event) { _, newEvent in
            guard let newEvent else { return }
            handle(newEvent.command)
        }
    }

    private func handle(_ command: CabinetEvent.Command) {
        switch command {
        case .move(let direction):
            move(direction)
        // Only a game the shelf shows: a search with no results keeps the
        // last focused game around.
        case .activate:
            if let game = shownFocusedGame { onPlay(game) }
        case .details:
            if let game = shownFocusedGame { onDetails(game) }
        case .toggleFavorite:
            if let game = shownFocusedGame {
                game.favorite.toggle()
                try? game.modelContext?.save()
            }
        case .random:
            focus(games.randomElement())
        case .previousLetter:
            jump(forward: false)
        case .nextLetter:
            jump(forward: true)
        case .previousSection, .nextSection, .back, .menu, .search, .character, .deleteCharacter:
            break
        }
    }

    private var shownFocusedGame: Game? {
        games.first { $0.persistentModelID == focusedGame?.persistentModelID }
    }

    private func move(_ direction: GridMoveDirection) {
        let games = games
        let index = focusedGame.flatMap { focused in games.firstIndex { $0.persistentModelID == focused.persistentModelID } }
        switch (installed.theme.layout, direction) {
        // Past either end, around to the other.
        case (.carousel, .left), (.wheel, .up), (.list, .up): focus(games[safe: (index ?? 0) - 1] ?? games.last)
        case (.carousel, .right), (.wheel, .down), (.list, .down): focus(games[safe: (index ?? -1) + 1] ?? games.first)
        case (.carousel, .up), (.wheel, .left), (.list, .left): onSectionStep(-1)
        case (.carousel, .down), (.wheel, .right), (.list, .right): onSectionStep(1)
        case (.grid, _):
            let target = GridNavigation.index(movingFrom: index, direction: direction, itemCount: games.count, columns: columns)
            focus(target.map { games[$0] })
        }
    }

    /// To the next or previous letter when the games run A to Z, else ten
    /// games along.
    private func jump(forward: Bool) {
        let games = games
        guard !games.isEmpty else { return }
        let index = focusedGame.flatMap { focused in games.firstIndex { $0.persistentModelID == focused.persistentModelID } } ?? 0
        let target: Int?
        if isTitleOrder {
            target = TitleBrowsing.jump(from: index, in: games.map(\.sortTitle), forward: forward)
        } else {
            target = min(max(index + (forward ? 10 : -10), 0), games.count - 1)
        }
        guard let target, target != index else { return }
        focus(games[target])
        onJump(isTitleOrder ? TitleBrowsing.letter(of: games[target].sortTitle) : "\(target + 1)")
    }

    private func focus(_ game: Game?) {
        guard let game else { return }
        focusedGame = game
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
