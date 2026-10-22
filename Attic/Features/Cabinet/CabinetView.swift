import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// One input to Cabinet Mode, from either the controller or the keyboard —
/// wrapped with a sequence number so repeating the same command still
/// registers as a change.
struct CabinetEvent: Equatable {
    enum Command: Equatable {
        case move(GridMoveDirection)
        case activate
        case toggleFavorite
        case previousSection
        case nextSection
        case back
        /// Start: opens or closes the menu.
        case menu
    }

    let command: Command
    let sequence: Int
}

/// Full-screen, controller-first "couch" mode — Attic's take on
/// LaunchBox's Cabinet Mode / Steam's Big Picture. Sections across the
/// top, the section's games in the theme's layout (see `CabinetShelf`),
/// over the focused game's art. Everything it draws comes from the
/// selected `CabinetTheme`. Runs in its own full-screen window so the
/// regular library window keeps its state underneath.
struct CabinetView: View {
    static let windowID = "cabinet"
    static let startInCabinetKey = "startInCabinet"

    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @Query(sort: \GameCollection.name) private var collections: [GameCollection]
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(CabinetThemeStore.self) private var themeStore
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var selection: LibrarySelection = .allGames
    /// The systems, or a section's games (see `CabinetTheme.Systems`).
    @State private var level = Level.systems
    @State private var focusedGame: Game?
    @State private var gameCount = 0
    @State private var event: CabinetEvent?
    @State private var eventSequence = 0
    /// The menu's open pages; empty while it's closed.
    @State private var menuPath: [CabinetMenuPage] = []
    @State private var menuEvent: CabinetEvent?
    @FocusState private var hasKeyboardFocus: Bool

    enum Level {
        case systems, games
    }

    var body: some View {
        let installed = themeStore.current
        let theme = installed.theme
        ZStack {
            CabinetBackdrop(game: level == .games ? focusedGame : nil)

            VStack(spacing: 0) {
                switch level {
                case .systems:
                    CabinetSystemsView(sections: sections, selection: $selection, onOpen: { send(.activate) })
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                case .games:
                    VStack(spacing: 0) {
                        CabinetHeader(sections: sections, selection: $selection, gameCount: gameCount)
                            .padding(.top, 36)

                        CabinetShelf(selection: selection, event: event, focusedGame: $focusedGame, gameCount: $gameCount,
                                     onSectionStep: stepSection(by:))
                            // A new Query per section; the shelf picks its own first game.
                            .id(selection)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if theme.showsHints {
                    CabinetHintBar(level: level, backGoesToSystems: theme.systems.isEnabled, onMenu: { send(.menu) })
                        .padding(.bottom, 28)
                }
            }

            if !menuPath.isEmpty {
                CabinetMenuView(path: $menuPath, event: menuEvent, onExit: exit)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: menuPath.isEmpty)
        .foregroundStyle(theme.palette.text.color)
        .tint(theme.palette.accent.color)
        .environment(\.cabinetTheme, installed)
        .background(theme.palette.background.color)
        .preferredColorScheme(.dark)
        .background(FullScreenWindowConfigurator())
        .missingBIOSAlert(isActive: gamepad.isCabinetActive)
        .failedLaunchAlert(isActive: gamepad.isCabinetActive)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        // Each layout decides what a direction does (see `CabinetShelf`).
        .onMoveCommand { direction in
            switch direction {
            case .left: send(.move(.left))
            case .right: send(.move(.right))
            case .up: send(.move(.up))
            case .down: send(.move(.down))
            @unknown default: break
            }
        }
        .onKeyPress(.return) { send(.activate); return .handled }
        .onKeyPress(.tab) { send(.nextSection); return .handled }
        .onKeyPress("m") { send(.menu); return .handled }
        .onExitCommand { send(.back) }
        .onChange(of: gamepad.lastEvent) { _, gamepadEvent in
            guard let gamepadEvent else { return }
            switch gamepadEvent.command {
            case .move(let direction): send(.move(direction))
            case .previousSection: send(.previousSection)
            case .nextSection: send(.nextSection)
            case .activate: send(.activate)
            case .toggleFavorite: send(.toggleFavorite)
            case .back: send(.back)
            case .toggleCabinet: send(.menu)
            }
        }
        .onChange(of: event) { _, newEvent in
            switch newEvent?.command {
            case .previousSection: stepSection(by: -1)
            case .nextSection: stepSection(by: 1)
            default: break // Game-level commands belong to the shelf.
            }
        }
        .onAppear {
            gamepad.isCabinetActive = true
            hasKeyboardFocus = true
            // Picks up themes added or edited since.
            themeStore.reload()
            level = themeStore.current.theme.systems.isEnabled ? .systems : .games
        }
        .onChange(of: theme.systems.isEnabled) { _, isEnabled in
            if !isEnabled { level = .games }
        }
        .onDisappear {
            gamepad.isCabinetActive = false
        }
    }

    /// Library shortcuts first, then non-empty collections, then every
    /// system that actually has games.
    private var sections: [CabinetSection] {
        [
            CabinetSection(selection: .allGames, title: String(localized: "All Games")),
            CabinetSection(selection: .favorites, title: String(localized: "Favorites")),
            CabinetSection(selection: .recentlyPlayed, title: String(localized: "Recently Played")),
            CabinetSection(selection: .recentlyAdded, title: String(localized: "Recently Added"))
        ] + collections
            .filter { !$0.games.isEmpty }
            .map { collection in
                let logo = CollectionFolders.image(named: CollectionFile.logoName, for: collection, root: CollectionFolders.root(in: emulationFolderStore.folder.root))
                    .flatMap(NSImage.init(contentsOf:))
                    .map { Image(nsImage: $0) }
                return CabinetSection(selection: .collection(collection.collectionID), title: collection.name, logo: logo)
            }
        + systems
            .filter { $0.gameCount > 0 }
            .orderedByCategory()
            .map { CabinetSection(selection: .system($0.systemID), title: $0.displayName, logo: $0.systemID.logo) }
    }

    /// While the menu is open, it gets every command but Start.
    private func send(_ command: CabinetEvent.Command) {
        eventSequence += 1
        let newEvent = CabinetEvent(command: command, sequence: eventSequence)
        switch command {
        case .menu:
            menuPath = menuPath.isEmpty ? [.main] : []
        case _ where !menuPath.isEmpty:
            menuEvent = newEvent
        case _ where level == .systems:
            switch command {
            case .move(.left), .move(.up), .previousSection: stepSection(by: -1)
            case .move(.right), .move(.down), .nextSection: stepSection(by: 1)
            case .activate: setLevel(.games)
            case .back: exit()
            case .move, .toggleFavorite, .menu: break
            }
        case .back:
            if themeStore.current.theme.systems.isEnabled { setLevel(.systems) } else { exit() }
        default:
            event = newEvent
        }
    }

    private func setLevel(_ newLevel: Level) {
        withAnimation(.snappy(duration: 0.3)) { level = newLevel }
    }

    private func stepSection(by offset: Int) {
        let all = sections
        guard !all.isEmpty else { return }
        let current = all.firstIndex { $0.selection == selection } ?? 0
        withAnimation(.snappy) {
            selection = all[((current + offset) % all.count + all.count) % all.count].selection
        }
    }

    private func exit() {
        gamepad.isCabinetActive = false
        dismissWindow(id: Self.windowID)
    }
}

struct CabinetSection: Identifiable, Hashable {
    let selection: LibrarySelection
    let title: String
    /// Systems show their logo instead of their name.
    var logo: Image? = nil
    var id: LibrarySelection { selection }

    /// For a section without a logo.
    var symbol: String {
        switch selection {
        case .allGames: "square.grid.3x3.fill"
        case .favorites: "star.fill"
        case .recentlyPlayed: "clock.fill"
        case .recentlyAdded: "sparkles"
        case .collection: "rectangle.stack.fill"
        case .system: "gamecontroller.fill"
        }
    }

    /// "Nintendo · 1990 · Console" for a system.
    var facts: String? {
        if case .system(let id) = selection { return SystemFacts.summary(for: id) }
        return nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection && lhs.title == rhs.title }
    func hash(into hasher: inout Hasher) { hasher.combine(selection) }
}

// MARK: - Header, hints and backdrop

private struct CabinetHeader: View {
    let sections: [CabinetSection]
    @Binding var selection: LibrarySelection
    let gameCount: Int

    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let theme = installed.theme
        HStack(spacing: 18) {
            Image(systemName: "lb.rectangle.roundedbottom.fill")
                .font(theme.largeFont())
                .foregroundStyle(theme.palette.secondaryText.color)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(sections) { section in
                            sectionButton(section, isSelected: section.selection == selection, theme: theme)
                                .id(section.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: selection, initial: true) { _, newSelection in
                    withAnimation(.snappy) { proxy.scrollTo(newSelection, anchor: .center) }
                }
            }

            Image(systemName: "rb.rectangle.roundedbottom.fill")
                .font(theme.largeFont())
                .foregroundStyle(theme.palette.secondaryText.color)

            if theme.header.showsGameCount || theme.header.showsClock {
                HStack(spacing: 20) {
                    if theme.header.showsGameCount {
                        Text("^[\(gameCount) game](inflect: true)")
                            .monospacedDigit()
                    }
                    if theme.header.showsClock {
                        TimelineView(.everyMinute) { context in
                            Text(context.date, format: .dateTime.hour().minute())
                                .monospacedDigit()
                        }
                    }
                }
                .font(theme.bodyFont(.medium))
                .foregroundStyle(theme.palette.secondaryText.color)
                .fixedSize()
                .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 40)
    }

    private func sectionButton(_ section: CabinetSection, isSelected: Bool, theme: CabinetTheme) -> some View {
        Button {
            withAnimation(.snappy) { selection = section.selection }
        } label: {
            Group {
                if theme.header.showsLogos, let logo = section.logo {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 34)
                        .opacity(isSelected ? 1 : 0.55)
                        .accessibilityLabel(section.title)
                } else {
                    Text(theme.cased(section.title))
                        .font(theme.largeFont(isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? theme.palette.text.color : theme.palette.secondaryText.color)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(isSelected ? theme.palette.surface.color : .clear, in: Capsule())
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(theme.palette.accent.color.opacity(0.7), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CabinetHintBar: View {
    let level: CabinetView.Level
    let backGoesToSystems: Bool
    let onMenu: () -> Void

    @Environment(GamepadInputMonitor.self) private var gamepad
    // Read so the hints update as soon as the layout changes.
    @Environment(ControllerSettingsStore.self) private var controllerSettings
    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let _ = controllerSettings.settings.layout
        HStack(spacing: 36) {
            switch level {
            case .systems:
                hint(gamepad.confirmButtonSymbol, "Open")
                hint("dpad.fill", "Browse")
                hint(gamepad.backButtonSymbol, "Exit")
            case .games:
                hint(gamepad.confirmButtonSymbol, "Play")
                hint(gamepad.favoriteButtonSymbol, "Favorite")
                hint("dpad.fill", "Browse")
                hint("lb.rectangle.roundedbottom.fill", "Sections")
                if backGoesToSystems {
                    hint(gamepad.backButtonSymbol, "Systems")
                } else {
                    hint(gamepad.backButtonSymbol, "Exit")
                }
            }
            Button(action: onMenu) {
                hint(gamepad.menuButtonSymbol, "Menu")
            }
            .buttonStyle(.plain)
        }
        .font(installed.theme.bodyFont())
        .foregroundStyle(installed.theme.palette.secondaryText.color)
    }

    private func hint(_ symbol: String, _ label: LocalizedStringKey) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
    }
}

/// The theme's picture, then the focused game's art per the theme —
/// blurred, darkened, cross-fading as focus moves.
private struct CabinetBackdrop: View {
    let game: Game?

    @Environment(\.cabinetTheme) private var installed
    @State private var image: CGImage?
    @State private var artURL: URL?

    var body: some View {
        let backdrop = installed.theme.backdrop
        // The filled images hang off a flexible Color as overlays so they
        // never size the layout themselves — as plain ZStack children,
        // their aspect-fill size grew the whole Cabinet Mode past the screen.
        installed.theme.palette.background.color
            .overlay {
                if let themeImage = installed.asset(backdrop.image).flatMap(NSImage.init(contentsOf:)) {
                    Image(nsImage: themeImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: backdrop.blur)
                        .opacity(1 - backdrop.dim)
                        .transition(.opacity)
                        .id(artURL)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: artURL)
            .task(id: [game?.persistentModelID.hashValue.description, backdrop.source.rawValue, String(backdrop.blur)]) {
                artURL = game.flatMap { CabinetArt.url(for: $0, backdrop.source) }
                guard let artURL else {
                    image = nil
                    return
                }
                // Blurred, so a small decode is plenty; sharp needs more.
                image = await CoverArtThumbnailCache.shared.thumbnail(for: artURL, maxPixelSize: backdrop.blur >= 20 ? 256 : 1920)
            }
    }
}

/// Which file a theme's art setting means for a game, falling back to
/// what the game has.
enum CabinetArt {
    static func url(for game: Game, _ source: CabinetTheme.Backdrop.Source) -> URL? {
        switch source {
        case .none: nil
        case .cover: game.coverArtURL
        case .screenshot: game.titleScreenURL ?? game.coverArtURL
        case .fanart: game.fanartURL ?? game.titleScreenURL ?? game.coverArtURL
        }
    }

    static func url(for game: Game, _ media: CabinetTheme.Details.Media) -> URL? {
        switch media {
        case .none: nil
        case .cover: url(for: game, CabinetTheme.Backdrop.Source.cover)
        case .screenshot: url(for: game, CabinetTheme.Backdrop.Source.screenshot)
        case .fanart: url(for: game, CabinetTheme.Backdrop.Source.fanart)
        }
    }
}

/// Puts Cabinet Mode's window into native full screen as soon as it appears.
private struct FullScreenWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowObservingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowObservingView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            // Toggling while SwiftUI is still setting the window up is
            // silently ignored, so wait until it's actually on screen and key.
            if window.isKeyWindow {
                enterFullScreen(window)
            } else {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.window else { return }
                        self.enterFullScreen(window)
                        if let observer = self.observer { NotificationCenter.default.removeObserver(observer) }
                        self.observer = nil
                    }
                }
            }
        }

        private func enterFullScreen(_ window: NSWindow) {
            guard !window.styleMask.contains(.fullScreen) else { return }
            DispatchQueue.main.async { window.toggleFullScreen(nil) }
        }
    }
}
