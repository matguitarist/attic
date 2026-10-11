import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence

/// One input to Big Box, from either the controller or the keyboard —
/// wrapped with a sequence number so repeating the same command still
/// registers as a change.
struct BigBoxEvent: Equatable {
    enum Command: Equatable {
        case move(GridMoveDirection)
        case activate
        case toggleFavorite
        case previousSection
        case nextSection
    }

    let command: Command
    let sequence: Int
}

/// Full-screen, controller-first "couch" mode — RomsBox's take on
/// LaunchBox's Big Box / Steam's Big Picture. Systems across the top, a
/// carousel of large covers, the focused game's details, and a blurred
/// cover backdrop. Runs in its own full-screen window so the regular
/// library window keeps its state underneath.
struct BigBoxView: View {
    static let windowID = "bigbox"
    static let startInBigBoxKey = "startInBigBox"

    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var selection: LibrarySelection = .allGames
    @State private var focusedGame: Game?
    @State private var event: BigBoxEvent?
    @State private var eventSequence = 0
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        ZStack {
            BigBoxBackdrop(coverURL: focusedGame?.coverArtURL)

            VStack(spacing: 0) {
                BigBoxSystemBar(sections: sections, selection: $selection)
                    .padding(.top, 36)

                BigBoxShelf(selection: selection, event: event, focusedGame: $focusedGame)
                    // A new Query per section; the shelf picks its own first game.
                    .id(selection)

                BigBoxHintBar()
                    .padding(.bottom, 28)
            }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .background(FullScreenWindowConfigurator())
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onMoveCommand { direction in
            switch direction {
            case .left: send(.move(.left))
            case .right: send(.move(.right))
            case .up: send(.previousSection)
            case .down: send(.nextSection)
            @unknown default: break
            }
        }
        .onKeyPress(.return) { send(.activate); return .handled }
        .onKeyPress(.tab) { send(.nextSection); return .handled }
        .onExitCommand(perform: exit)
        .onChange(of: gamepad.lastEvent) { _, gamepadEvent in
            guard let gamepadEvent else { return }
            switch gamepadEvent.command {
            case .move(let direction) where direction == .left || direction == .right:
                send(.move(direction))
            // Up/down switch systems too, so a pad without (or with
            // awkward) shoulder buttons can still get everywhere.
            case .move(.up), .previousSection: send(.previousSection)
            case .move(.down), .nextSection: send(.nextSection)
            case .move: break
            case .activate: send(.activate)
            case .toggleFavorite: send(.toggleFavorite)
            case .back, .toggleBigBox: exit()
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
            gamepad.isBigBoxActive = true
            hasKeyboardFocus = true
        }
        .onDisappear {
            gamepad.isBigBoxActive = false
        }
    }

    /// Library shortcuts first, then every system that actually has games.
    private var sections: [BigBoxSection] {
        [
            BigBoxSection(selection: .allGames, title: String(localized: "All Games")),
            BigBoxSection(selection: .favorites, title: String(localized: "Favorites")),
            BigBoxSection(selection: .recentlyPlayed, title: String(localized: "Recently Played"))
        ] + systems
            .filter { $0.gameCount > 0 }
            .orderedByCategory()
            .map { BigBoxSection(selection: .system($0.systemID), title: $0.displayName) }
    }

    private func send(_ command: BigBoxEvent.Command) {
        eventSequence += 1
        event = BigBoxEvent(command: command, sequence: eventSequence)
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
        gamepad.isBigBoxActive = false
        dismissWindow(id: Self.windowID)
    }
}

struct BigBoxSection: Identifiable, Hashable {
    let selection: LibrarySelection
    let title: String
    var id: LibrarySelection { selection }
}

// MARK: - Shelf (carousel + details)

/// The covers carousel and focused game's details for one section. Owns
/// the section's query, so switching sections swaps the whole shelf.
private struct BigBoxShelf: View {
    @Query private var games: [Game]
    let event: BigBoxEvent?
    @Binding var focusedGame: Game?

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @State private var scrolledID: PersistentIdentifier?

    init(selection: LibrarySelection, event: BigBoxEvent?, focusedGame: Binding<Game?>) {
        let sort: [SortDescriptor<Game>] = selection == .recentlyPlayed
            ? [SortDescriptor(\.lastPlayedDate, order: .reverse)]
            : [SortDescriptor(\.sortTitle)]
        _games = Query(filter: GameGridView.selectionPredicate(selection), sort: sort)
        self.event = event
        _focusedGame = focusedGame
    }

    var body: some View {
        Group {
            if games.isEmpty {
                ContentUnavailableView("No Games Here", systemImage: "gamecontroller", description: Text("Switch systems with LB / RB."))
                    .frame(maxHeight: .infinity)
            } else {
                // Explicit heights: a horizontal ScrollView in a stack grabs
                // all the height it's offered, which pushed the details (and
                // the system bar above) off screen.
                GeometryReader { geometry in
                    let infoHeight: CGFloat = 200
                    let coverHeight = max(180, geometry.size.height - infoHeight - 40)
                    VStack(spacing: 24) {
                        carousel(coverHeight: coverHeight, width: geometry.size.width)
                            .frame(height: coverHeight)
                        BigBoxGameInfo(game: focusedGame)
                            .frame(height: infoHeight, alignment: .top)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .onAppear { focus(games.first, animated: false) }
        .onChange(of: scrolledID) { _, id in
            // Trackpad/mouse scrolling moves focus too.
            if let id, id != focusedGame?.persistentModelID, let game = games.first(where: { $0.persistentModelID == id }) {
                focusedGame = game
            }
        }
        .onChange(of: event) { _, newEvent in
            guard let newEvent else { return }
            handle(newEvent.command)
        }
    }

    private func carousel(coverHeight: CGFloat, width: CGFloat) -> some View {
        let coverWidth = coverHeight * 0.75

        return ScrollView(.horizontal) {
                LazyHStack(spacing: 36) {
                    ForEach(games) { game in
                        let isFocused = game.persistentModelID == focusedGame?.persistentModelID
                        BigBoxCover(game: game, isFocused: isFocused)
                            .frame(width: coverWidth, height: coverHeight)
                            .id(game.persistentModelID)
                            .onTapGesture(count: 2) { play(game) }
                            .onTapGesture { focus(game) }
                    }
                }
                .scrollTargetLayout()
            }
            // Centers the first and last covers instead of pinning them to
            // the screen edges.
            .contentMargins(.horizontal, max(0, (width - coverWidth) / 2), for: .scrollContent)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            // `.never`, not `.hidden`: with "Show scroll bars: Always" set
            // in System Settings, `.hidden` still draws them.
            .scrollIndicators(.never)
    }

    private func handle(_ command: BigBoxEvent.Command) {
        switch command {
        case .move(let direction):
            let index = focusedGame.flatMap { focused in games.firstIndex { $0.persistentModelID == focused.persistentModelID } } ?? 0
            switch direction {
            case .left: focus(games[safe: index - 1])
            case .right: focus(games[safe: index + 1])
            default: break
            }
        case .activate:
            if let focusedGame { play(focusedGame) }
        case .toggleFavorite:
            if let focusedGame {
                focusedGame.favorite.toggle()
                try? focusedGame.modelContext?.save()
            }
        case .previousSection, .nextSection:
            break
        }
    }

    private func focus(_ game: Game?, animated: Bool = true) {
        guard let game else { return }
        focusedGame = game
        if animated {
            withAnimation(.snappy(duration: 0.25)) { scrolledID = game.persistentModelID }
        } else {
            scrolledID = game.persistentModelID
        }
    }

    private func play(_ game: Game) {
        focus(game)
        launchCoordinator.play(game: game, retroArchStore: retroArchStore)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Pieces

private struct BigBoxCover: View {
    let game: Game
    let isFocused: Bool

    var body: some View {
        // No card behind the art: on the dark backdrop, covers of any shape
        // read better floating on their own.
        GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false)
            .overlay(alignment: .topTrailing) {
                if game.favorite {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 4)
                        .padding(14)
                }
            }
            .scaleEffect(isFocused ? 1 : 0.72)
            .opacity(isFocused ? 1 : 0.45)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 30, y: 16)
            .animation(.snappy(duration: 0.25), value: isFocused)
    }
}

private struct BigBoxGameInfo: View {
    let game: Game?

    @Environment(LaunchCoordinator.self) private var launchCoordinator

    var body: some View {
        if let game {
            VStack(spacing: 10) {
                Text(game.title)
                    .font(.system(size: 44, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(metadata(for: game))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if launchCoordinator.state == .running(gameID: game.persistentModelID) {
                    Label("Playing", systemImage: "gamecontroller.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                } else if case .failed(let message) = launchCoordinator.state {
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.red)
                } else if let description = game.gameDescription {
                    Text(description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1000)
                }
            }
            .padding(.horizontal, 60)
            .id(game.persistentModelID)
            .transition(.opacity)
        }
    }

    private func metadata(for game: Game) -> String {
        var parts: [String] = []
        if let system = game.system?.displayName { parts.append(system) }
        if let year = game.releaseDate.map({ Calendar.current.component(.year, from: $0) }) { parts.append(String(year)) }
        if let genre = game.genre { parts.append(genre) }
        // `players` is free text from scrapers ("1", "1-2", "1-4"), so it
        // can't drive a plural — label it instead.
        if let players = game.players { parts.append(String(localized: "Players: \(players)")) }
        if game.playCount > 0 { parts.append(String(localized: "Played \(game.playCount)×")) }
        return parts.joined(separator: "  ·  ")
    }
}

private struct BigBoxSystemBar: View {
    let sections: [BigBoxSection]
    @Binding var selection: LibrarySelection

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "lb.rectangle.roundedbottom.fill")
                .font(.title)
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(sections) { section in
                            let isSelected = section.selection == selection
                            Button {
                                withAnimation(.snappy) { selection = section.selection }
                            } label: {
                                Text(section.title)
                                    .font(.title2.weight(isSelected ? .bold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .glassEffect(isSelected ? .regular : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
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
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }
}

private struct BigBoxHintBar: View {
    var body: some View {
        HStack(spacing: 36) {
            hint("a.circle.fill", "Play")
            hint("y.circle.fill", "Favorite")
            hint("dpad.fill", "Browse")
            hint("b.circle.fill", "Exit")
        }
        .font(.title3)
        .foregroundStyle(.secondary)
    }

    private func hint(_ symbol: String, _ label: LocalizedStringKey) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
    }
}

/// The focused game's cover, blown up, blurred and darkened behind
/// everything — cross-fades as focus moves.
private struct BigBoxBackdrop: View {
    let coverURL: URL?
    @State private var image: CGImage?

    var body: some View {
        // The filled image hangs off a flexible Color as an overlay so it
        // never sizes the layout itself — as a plain ZStack child, its
        // aspect-fill size grew the whole Big Box past the screen.
        Color.black
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60)
                        .opacity(0.55)
                        .transition(.opacity)
                        .id(coverURL)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: coverURL)
        .task(id: coverURL) {
            guard let coverURL else {
                image = nil
                return
            }
            // Heavily blurred, so a small decode is plenty.
            image = await CoverArtThumbnailCache.shared.thumbnail(for: coverURL, maxPixelSize: 256)
        }
    }
}

/// Puts Big Box's window into native full screen as soon as it appears.
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
