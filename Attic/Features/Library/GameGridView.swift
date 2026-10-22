import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

struct GameGridView: View {
    @Query private var games: [Game]
    @Binding var selectedGame: Game?
    @State private var viewportHeight: CGFloat = 0
    /// Several games selected at once (⌘-click, ⇧-click, ⌘A). Empty or a
    /// single game means the plain one-game selection in `selectedGame`.
    @Binding var multiSelection: [Game]
    private let sortOrder: GameSortOrder

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(GameInfoEditor.self) private var infoEditor
    @Environment(CollectionCoordinator.self) private var collectionCoordinator
    @Query private var shownCollection: [GameCollection]

    private let cellScale: CGFloat

    @State private var availableWidth: CGFloat = 0
    @FocusState private var isGridFocused: Bool

    // Fixed (not ranged) min==max width so every column — and therefore
    // every row — lines up identically regardless of window width; the grid
    // just fits however many equal-width columns fit. Scaled live by the
    // zoom slider rather than fixed at one size.
    //
    // The layout itself must stay `.adaptive`: an earlier version built N
    // `.fixed` columns from the measured width, which made the grid's ideal
    // width depend on that measurement — inside the inspector's split view
    // that fed back into the width and crashed AppKit with an endless
    // update-constraints loop. `columnCount` below only *mirrors* the
    // adaptive layout's own arithmetic, for arrow-key/gamepad up/down moves,
    // and never drives layout.
    static let baseCellWidth: CGFloat = 160
    private static let spacing: CGFloat = 20
    private static let padding: CGFloat = 16
    private var cellWidth: CGFloat { Self.baseCellWidth * cellScale }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth), spacing: Self.spacing)]
    }
    private var columnCount: Int {
        GridNavigation.columnCount(availableWidth: availableWidth - Self.padding * 2, cellWidth: cellWidth, spacing: Self.spacing)
    }

    /// Each change picks a game at random.
    private let randomPicks: Int

    init(selection: LibrarySelection, searchText: String, sortOrder: GameSortOrder, cellScale: CGFloat, selectedGame: Binding<Game?>, multiSelection: Binding<[Game]>, randomPicks: Int = 0) {
        _multiSelection = multiSelection
        self.randomPicks = randomPicks
        self.cellScale = cellScale
        // Recently Played always shows most-recent-first, regardless of the
        // toolbar's sort picker — that's the one thing that view is for.
        let effectiveSortOrder: GameSortOrder = switch selection {
        case .recentlyPlayed: .lastPlayed
        case .recentlyAdded: .dateAdded
        default: sortOrder
        }

        // `Bool` isn't `Comparable`, so SwiftData's SortDescriptor can't sort
        // by `favorite` directly — fetch title-sorted and, for
        // `.favoriteFirst`, stably reorder in memory instead.
        _games = Query(
            filter: Self.predicate(selection: selection, searchText: searchText),
            sort: Self.sortDescriptors(for: effectiveSortOrder)
        )
        _selectedGame = selectedGame
        self.sortOrder = effectiveSortOrder
        limit = selection == .recentlyAdded ? Self.recentlyAddedCount : nil
        // Only matches when a collection is showing, for "Remove from…".
        let collectionID: UUID = if case .collection(let id) = selection { id } else { UUID() }
        _shownCollection = Query(filter: #Predicate<GameCollection> { $0.collectionID == collectionID })
    }

    /// How many games Recently Added shows.
    static let recentlyAddedCount = 100
    private let limit: Int?

    private var displayedGames: [Game] {
        if let limit { return Array(games.prefix(limit)) }
        if sortOrder == .systemThenRelease { return Self.bySystemThenRelease(games) }
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
        ScrollViewReader { proxy in
            grid
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
                .focusable()
                .focusEffectDisabled()
                .focused($isGridFocused)
                .onAppear { isGridFocused = true }
                .onMoveCommand { direction in
                    switch direction {
                    case .up: move(.up, proxy: proxy)
                    case .down: move(.down, proxy: proxy)
                    case .left: move(.left, proxy: proxy)
                    case .right: move(.right, proxy: proxy)
                    @unknown default: break
                    }
                }
                .onCommand(#selector(NSResponder.selectAll(_:))) {
                    selectAll()
                }
                .onExitCommand {
                    multiSelection = []
                }
                .onKeyPress(.return) {
                    guard let selectedGame else { return .ignored }
                    play(selectedGame)
                    return .handled
                }
                .onChange(of: gamepad.lastEvent) { _, event in
                    guard let event, !gamepad.isCabinetActive else { return }
                    handle(event.command, proxy: proxy)
                }
                .onChange(of: randomPicks) { pickRandom(proxy: proxy) }
        }
    }

    private var grid: some View {
        ScrollView {
            if games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "gamecontroller",
                    description: Text("No games match this selection.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: Self.spacing) {
                    ForEach(displayedGames) { game in
                        GameCoverCell(game: game, isSelected: isSelected(game), width: cellWidth)
                            // Both gestures attached together let SwiftUI
                            // disambiguate by tap count itself (waiting
                            // briefly after one tap to see if a second
                            // arrives) rather than needing to do that by hand.
                            .onTapGesture(count: 2) { play(game) }
                            .onTapGesture(count: 1) {
                                click(game)
                                isGridFocused = true
                            }
                            .contextMenu { contextMenuContent(for: game) }
                            .id(game.persistentModelID)
                    }
                }
                .padding(Self.padding)
                // Clicking between or below the covers deselects, as in
                // Finder; a cover's own click wins over this one. At least
                // as tall as the view, so the space below the last row
                // counts too.
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedGame = nil
                    multiSelection = []
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
            viewportHeight = height
        }
        .background(Color.contentBackground)
        // One key with plural variants in the String Catalog, rather than an
        // English-only singular/plural ternary.
        .navigationSubtitle(String(localized: "\(games.count) games"))
    }

    private func handle(_ command: GamepadCommand, proxy: ScrollViewProxy) {
        switch command {
        case .move(let direction):
            move(direction, proxy: proxy)
        case .activate:
            if let selectedGame { play(selectedGame) }
        case .toggleFavorite:
            if let selectedGame {
                selectedGame.favorite.toggle()
                try? selectedGame.modelContext?.save()
            }
        case .previousSection, .nextSection, .back, .toggleCabinet:
            break // Owned by LibraryBrowserView.
        case .search, .random, .previousLetter, .nextLetter:
            break // Cabinet Mode's.
        }
    }

    private func move(_ direction: GridMoveDirection, proxy: ScrollViewProxy) {
        let items = displayedGames
        let currentIndex = selectedGame.flatMap { selected in
            items.firstIndex { $0.persistentModelID == selected.persistentModelID }
        }
        guard let newIndex = GridNavigation.index(
            movingFrom: currentIndex,
            direction: direction,
            itemCount: items.count,
            columns: columnCount
        ) else { return }

        let game = items[newIndex]
        multiSelection = []
        selectedGame = game
        // `anchor: nil` scrolls only as far as needed to reveal the cell,
        // rather than snapping every move to the top or center.
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(game.persistentModelID, anchor: nil)
        }
    }

    /// Selects a game at random among those shown (another than the one
    /// selected), and brings it into view.
    private func pickRandom(proxy: ScrollViewProxy) {
        let items = displayedGames
        let others = items.count > 1 ? items.filter { $0.persistentModelID != selectedGame?.persistentModelID } : items
        guard let game = others.randomElement() else { return }
        multiSelection = []
        selectedGame = game
        isGridFocused = true
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(game.persistentModelID, anchor: .center)
        }
    }

    private var isMultiSelecting: Bool { multiSelection.count > 1 }

    private func isSelected(_ game: Game) -> Bool {
        if isMultiSelecting {
            return multiSelection.contains { $0.persistentModelID == game.persistentModelID }
        }
        return game.persistentModelID == selectedGame?.persistentModelID
    }

    /// Finder-style clicks: ⌘ adds or removes one game, ⇧ selects the range
    /// from the last plainly clicked game, a plain click selects just one.
    private func click(_ game: Game) {
        let modifiers = NSEvent.modifierFlags
        let id = game.persistentModelID
        if modifiers.contains(.command) {
            var games = isMultiSelecting ? multiSelection : [selectedGame].compactMap { $0 }
            if let index = games.firstIndex(where: { $0.persistentModelID == id }) {
                games.remove(at: index)
                if selectedGame?.persistentModelID == id { selectedGame = games.last }
            } else {
                games.append(game)
                selectedGame = game
            }
            multiSelection = games.count > 1 ? games : []
            if games.count == 1 { selectedGame = games[0] }
        } else if modifiers.contains(.shift), let anchor = selectedGame {
            let items = displayedGames
            guard let from = items.firstIndex(where: { $0.persistentModelID == anchor.persistentModelID }),
                  let to = items.firstIndex(where: { $0.persistentModelID == id }) else {
                multiSelection = []
                selectedGame = game
                return
            }
            let range = items[min(from, to)...max(from, to)]
            multiSelection = range.count > 1 ? Array(range) : []
        } else {
            multiSelection = []
            selectedGame = game
        }
    }

    /// ⌘A / Edit › Select All: every game currently shown, e.g. all the
    /// results of a search.
    private func selectAll() {
        let items = displayedGames
        guard items.count > 1 else {
            selectedGame = items.first
            return
        }
        if selectedGame == nil || !items.contains(where: { $0.persistentModelID == selectedGame?.persistentModelID }) {
            selectedGame = items.first
        }
        multiSelection = items
    }

    private func play(_ game: Game) {
        selectedGame = game
        launchCoordinator.play(game: game, retroArchStore: retroArchStore)
    }

    @ViewBuilder
    private func contextMenuContent(for game: Game) -> some View {
        // Right-clicking inside a multi-selection acts on all of it; on a
        // game outside it, just on that game (as in Finder).
        if isMultiSelecting, isSelected(game) {
            MultipleGamesMenuItems(games: multiSelection, shownCollection: shownCollection.first)
        } else {
            singleGameMenuContent(for: game)
        }
    }

    @ViewBuilder
    private func singleGameMenuContent(for game: Game) -> some View {
        let target = resolvedTarget(for: game)
        let isRunningThisGame = launchCoordinator.state == .running(gameID: game.persistentModelID)
        let isBusy = launchCoordinator.state == .launching || isRunningThisGame

        Button(isRunningThisGame ? String(localized: "Running…") : String(localized: "Play")) {
            play(game)
        }
        .disabled(target == nil || isBusy)

        Menu("Launch With") {
            LaunchWithMenuItems(game: game)
        }

        Divider()

        Button(game.favorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) {
            game.favorite.toggle()
            try? game.modelContext?.save()
        }

        Button("Edit Info…") {
            selectedGame = game
            infoEditor.game = game
        }

        AddToCollectionMenu(game: game)

        if let collection = shownCollection.first {
            Button("Remove from “\(collection.name)”") {
                collection.setContains(game, false)
                try? game.modelContext?.save()
            }
        }

        Divider()

        Menu("Scrape Info") {
            ScrapeMenuItems(game: game)
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.romAbsoluteURL])
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
        case .recentlyAdded:
            return #Predicate<Game> { $0.dateAdded != nil }
        case .system(let canonicalID):
            let systemID = canonicalID.rawValue
            return #Predicate<Game> { $0.systemCanonicalID == systemID }
        case .collection(let collectionID):
            return #Predicate<Game> { game in game.collections.contains { $0.collectionID == collectionID } }
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
        case .recentlyAdded:
            if query.isEmpty {
                return #Predicate<Game> { $0.dateAdded != nil }
            }
            return #Predicate<Game> { $0.dateAdded != nil && $0.title.localizedStandardContains(query) }
        case .system(let canonicalID):
            let systemID = canonicalID.rawValue
            if query.isEmpty {
                return #Predicate<Game> { $0.systemCanonicalID == systemID }
            }
            return #Predicate<Game> { $0.systemCanonicalID == systemID && $0.title.localizedStandardContains(query) }
        case .collection(let collectionID):
            if query.isEmpty {
                return #Predicate<Game> { game in game.collections.contains { $0.collectionID == collectionID } }
            }
            return #Predicate<Game> { game in
                game.collections.contains { $0.collectionID == collectionID } && game.title.localizedStandardContains(query)
            }
        }
    }

    /// Grouped by system in the sidebar's order, oldest first within each;
    /// games with no release date after the dated ones, by title (the
    /// query's order).
    static func bySystemThenRelease(_ games: [Game]) -> [Game] {
        let systems = Dictionary(games.compactMap(\.system).map { ($0.canonicalID, $0) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(uniqueKeysWithValues: systems.values.sorted(by: GameSystem.displayOrder).enumerated().map { ($1.canonicalID, $0) })
        return games.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            let (systemA, systemB) = (order[a.systemCanonicalID] ?? .max, order[b.systemCanonicalID] ?? .max)
            if systemA != systemB { return systemA < systemB }
            switch (a.releaseDate, b.releaseDate) {
            case let (dateA?, dateB?) where dateA != dateB: return dateA < dateB
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }

    private static func sortDescriptors(for order: GameSortOrder) -> [SortDescriptor<Game>] {
        switch order {
        case .title, .favoriteFirst, .systemThenRelease:
            [SortDescriptor(\.sortTitle)]
        case .lastPlayed:
            [SortDescriptor(\.lastPlayedDate, order: .reverse)]
        case .dateAdded:
            [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.sortTitle)]
        }
    }
}
