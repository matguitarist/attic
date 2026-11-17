import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// What the editor's preview shows.
enum ThemePreviewPage: String, CaseIterable, Identifiable {
    case games, page, systems, menu, marquee
    var id: Self { self }

    var title: String {
        switch self {
        case .games: String(localized: "Games")
        case .page: String(localized: "Game Page")
        case .systems: String(localized: "Systems")
        case .menu: String(localized: "Menu")
        case .marquee: String(localized: "Marquee")
        }
    }
}

/// Cabinet Mode as the theme being edited draws it, with the library's
/// own games, scaled down from a 1280 × 720 screen so type and spacing
/// read as they will on the TV. Looking only: clicks pick a game, nothing
/// else.
struct ThemePreview: View {
    let installed: CabinetThemeStore.Installed
    let page: ThemePreviewPage
    let sections: [CabinetSection]
    @Binding var selection: LibrarySelection

    static let stage = CGSize(width: 1280, height: 720)

    @State private var focusedGame: Game?
    @State private var gameCount = 0
    @State private var browse = CabinetBrowse()
    @State private var menuPath: [CabinetMenuPage] = [.main]
    @State private var marquee = CabinetMarqueeModel()

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.stage.width, geometry.size.height / Self.stage.height)
            // Laid out at full size from the top left and scaled from there,
            // so it never reaches up under the toolbar: Cabinet Mode's
            // backdrop ignores the safe area, and stretched into the
            // toolbar's, it came out taller and shifted.
            stage
                .frame(width: Self.stage.width, height: Self.stage.height)
                .clipped()
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.stage.width * scale, height: Self.stage.height * scale, alignment: .topLeading)
                .clipped()
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onChange(of: marqueeKey, initial: true) {
            marquee.theme = installed.theme
            marquee.show(focusedGame, section: section)
        }
    }

    private var section: CabinetSection? { sections.first { $0.selection == selection } }

    private var marqueeKey: [AnyHashable] { [installed.theme, focusedGame?.persistentModelID, selection] }

    private var stage: some View {
        let theme = installed.theme
        return ZStack {
            CabinetBackdrop(game: page == .systems ? nil : focusedGame,
                            fallback: page == .systems ? section?.ownArt(.fanart) : nil,
                            allowsVideo: false)
            switch page {
            case .games, .menu:
                VStack(spacing: 0) {
                    CabinetHeader(sections: sections, selection: $selection, gameCount: gameCount)
                        .padding(.top, 36)
                    ThemePreviewShelf(selection: selection, focusedGame: $focusedGame, gameCount: $gameCount)
                        .id(selection)
                    if theme.showsHints {
                        CabinetHintBar(level: .games, backGoesToSystems: theme.systems.isEnabled, isFiltered: false, onMenu: {})
                            .padding(.bottom, 28)
                    }
                }
                if page == .menu {
                    CabinetMenuView(path: $menuPath, event: nil, onExit: {}, onSurprise: {}, onSearch: {},
                                    game: focusedGame, section: section)
                        // Its toggles change the real settings.
                        .allowsHitTesting(false)
                }
            case .page:
                // The shelf picks the game the page shows.
                ThemePreviewShelf(selection: selection, focusedGame: $focusedGame, gameCount: $gameCount)
                    .id(selection)
                    .opacity(0)
                if let focusedGame {
                    CabinetGamePage(game: focusedGame, event: nil, onPlay: { _ in }, onClose: {})
                        .id(focusedGame.persistentModelID)
                }
            case .systems:
                VStack(spacing: 0) {
                    CabinetSystemsView(sections: sections, selection: $selection, onOpen: {})
                    if theme.showsHints {
                        CabinetHintBar(level: .systems, backGoesToSystems: true, isFiltered: false, onMenu: {})
                            .padding(.bottom, 28)
                    }
                }
            case .marquee:
                ThemePreviewShelf(selection: selection, focusedGame: $focusedGame, gameCount: $gameCount)
                    .id(selection)
                    .opacity(0)
                Color.black
                // A common marquee screen's shape, 32:9 or so.
                CabinetMarqueeView(model: marquee)
                    .frame(width: Self.stage.width, height: Self.stage.width * 9 / 32)
                    // Its edges, on the black around it.
                    .overlay(Rectangle().strokeBorder(.white.opacity(0.25), lineWidth: 2))
            }
        }
        .environment(browse)
        .foregroundStyle(theme.palette.text.color)
        .tint(theme.palette.accent.color)
        .environment(\.cabinetTheme, installed)
        .background(theme.palette.background.color)
        .environment(\.colorScheme, .dark)
    }
}

/// A section's games in the theme's layout, the second one focused so
/// there are games on both sides; clicking one focuses it.
private struct ThemePreviewShelf: View {
    @Query private var games: [Game]
    @Binding var focusedGame: Game?
    @Binding var gameCount: Int
    @State private var columns = 1
    @Environment(\.cabinetTheme) private var installed

    init(selection: LibrarySelection, focusedGame: Binding<Game?>, gameCount: Binding<Int>) {
        var descriptor = FetchDescriptor(predicate: GameGridView.selectionPredicate(selection), sortBy: [SortDescriptor(\Game.sortTitle)])
        // Enough to fill any layout; the preview never scrolls far.
        descriptor.fetchLimit = 60
        _games = Query(descriptor)
        _focusedGame = focusedGame
        _gameCount = gameCount
    }

    var body: some View {
        Group {
            if games.isEmpty {
                ContentUnavailableView("No Games Here", systemImage: "gamecontroller")
                    .frame(maxHeight: .infinity)
            } else {
                let shelf = CabinetShelfContent(games: games, focusedID: focusedGame?.persistentModelID,
                                                onFocus: { focusedGame = $0 }, onPlay: { focusedGame = $0 })
                CabinetLayoutSwitch(shelf: shelf, layout: installed.theme.layout, columns: $columns)
            }
        }
        .onChange(of: games.count, initial: true) { _, count in gameCount = count }
        .onAppear {
            if focusedGame.map({ games.contains($0) }) != true { focusedGame = games.dropFirst().first ?? games.first }
        }
    }
}
