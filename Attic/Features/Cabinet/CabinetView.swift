import SwiftUI
import AtticLibraryScanning
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
        /// X: the game's page.
        case details
        /// Select: the on-screen keyboard.
        case search
        /// Right stick click: a random game.
        case random
        /// L2 / R2: the previous or next letter.
        case previousLetter
        case nextLetter
        /// Typed on a Mac keyboard into the search.
        case character(Character)
        case deleteCharacter
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
    @State private var builtSections: [CabinetSection] = []
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(CabinetThemeStore.self) private var themeStore
    @AppStorage(CabinetSystemsView.playsVideosKey) private var playsSystemVideos = false
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore

    /// The first section once they're built (see `sections`).
    @State private var selection: LibrarySelection = .favorites
    /// The systems, or a section's games (see `CabinetTheme.Systems`).
    @State private var level = Level.systems
    @State private var focusedGame: Game?
    @State private var gameCount = 0
    @State private var event: CabinetEvent?
    @State private var eventSequence = 0
    /// The menu's open pages; empty while it's closed.
    @State private var menuPath: [CabinetMenuPage] = []
    @State private var menuEvent: CabinetEvent?
    @State private var browse = CabinetBrowse()
    @State private var isSearching = false
    @State private var searchEvent: CabinetEvent?
    /// The game whose page is open.
    @State private var pageGame: Game?
    @State private var pageEvent: CabinetEvent?
    /// Select on the systems: the section opens on a random game.
    @State private var opensRandom = false
    /// The letter an L2/R2 jump landed on, shown for a moment.
    @State private var jumpLabel: String?
    @FocusState private var hasKeyboardFocus: Bool

    enum Level {
        case systems, games
    }

    var body: some View {
        let installed = themeStore.current
        let theme = installed.theme
        ZStack {
            // On the systems, the system's own fan art.
            CabinetBackdrop(game: level == .games ? (pageGame ?? focusedGame) : nil,
                            fallback: level == .systems ? sections.first { $0.selection == selection }?.ownArt(.fanart) : nil,
                            fallbackVideo: systemBackdropVideo,
                            // The game page plays its own.
                            allowsVideo: pageGame == nil && menuPath.isEmpty && !isSearching)

            VStack(spacing: 0) {
                switch level {
                case .systems:
                    CabinetSystemsView(sections: sections, selection: $selection, onOpen: { send(.activate) })
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                case .games:
                    VStack(spacing: 0) {
                        CabinetHeader(sections: sections, selection: $selection, gameCount: gameCount, chips: browse.chips)
                            .padding(.top, 36)

                        CabinetShelf(selection: selection, search: browse.appliedSearch, event: event,
                                     focusedGame: $focusedGame, gameCount: $gameCount,
                                     startsRandom: opensRandom, onSectionStep: stepSection(by:),
                                     onPlay: play, onDetails: showDetails, onJump: showJump)
                            // A new Query per section, and per search (which
                            // looks through every game); the shelf picks its
                            // own first game.
                            .id("\(selection)|\(browse.appliedSearch)")
                            .onAppear { opensRandom = false }
                    }
                    .opacity(pageGame == nil ? 1 : 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if theme.showsHints && pageGame == nil {
                    CabinetHintBar(level: level, backGoesToSystems: theme.systems.isEnabled, isFiltered: browse.isFiltered,
                                   onMenu: { send(.menu) })
                        .padding(.bottom, 28)
                }
            }

            if let pageGame {
                CabinetGamePage(game: pageGame, event: pageEvent, onPlay: play, onClose: { closePage() })
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }

            if isSearching {
                CabinetSearchView(browse: browse, event: searchEvent, resultCount: gameCount, onDone: { isSearching = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let jumpLabel {
                Text(verbatim: jumpLabel)
                    .font(theme.font(size: 120, weight: .heavy))
                    .frame(width: 200, height: 200)
                    .background(theme.palette.surface.color, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(theme.palette.accent.color, lineWidth: 3))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if !menuPath.isEmpty {
                CabinetMenuView(path: $menuPath, event: menuEvent, onExit: exit,
                                onSurprise: { menuPath = []; send(.random) },
                                onSearch: { menuPath = []; send(.search) })
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: menuPath.isEmpty)
        .animation(.snappy(duration: 0.25), value: isSearching)
        .animation(.snappy(duration: 0.25), value: pageGame == nil)
        .environment(browse)
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
        .onKeyPress(.delete) { send(.deleteCharacter); return .handled }
        // Letter jumps on any keyboard layout.
        .onKeyPress(.pageUp) { send(.previousLetter); return .handled }
        .onKeyPress(.pageDown) { send(.nextLetter); return .handled }
        // While searching, letters type; otherwise i (or space) opens
        // the game's page, f favorites, m the menu, / searches, r picks a
        // random game, [ and ] jump letters.
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.whitespaces)) { press in
            guard let character = press.characters.first else { return .ignored }
            if isSearching {
                press.characters.forEach { send(.character($0)) }
                return .handled
            }
            switch character {
            case "i", " ": send(.details)
            case "f": send(.toggleFavorite)
            case "m": send(.menu)
            case "/": send(.search)
            case "r": send(.random)
            case "[": send(.previousLetter)
            case "]": send(.nextLetter)
            default: return .ignored
            }
            return .handled
        }
        .onExitCommand { send(.back) }
        .onChange(of: gamepad.cabinetEvent) { _, gamepadEvent in
            guard let gamepadEvent else { return }
            switch gamepadEvent.command {
            case .move(let direction): send(.move(direction))
            case .previousSection: send(.previousSection)
            case .nextSection: send(.nextSection)
            case .activate: send(.activate)
            case .details: send(.details)
            case .toggleFavorite: send(.toggleFavorite)
            case .back: send(.back)
            case .toggleCabinet: send(.menu)
            case .search: send(.search)
            case .random: send(.random)
            case .previousLetter: send(.previousLetter)
            case .nextLetter: send(.nextLetter)
            }
        }
        .onChange(of: event) { _, newEvent in
            switch newEvent?.command {
            case .previousSection: stepSection(by: -1)
            case .nextSection: stepSection(by: 1)
            default: break // Game-level commands belong to the shelf.
            }
        }
        .onChange(of: sectionsKey, initial: true) {
            builtSections = buildSections()
            // A collection hidden or emptied meanwhile.
            if !builtSections.contains(where: { $0.selection == selection }), let first = builtSections.first {
                selection = first.selection
            }
        }
        .onAppear {
            CabinetWindows.hideOthers()
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
            CabinetWindows.showOthers()
        }
        // Quitting a game (Select + Start, or RetroArch's menu) comes back
        // here, not to whichever Attic window macOS would pick.
        .onChange(of: launchCoordinator.state) { old, new in
            if case .running = old, new == .idle { CabinetWindows.bringCabinetForward() }
        }
    }

    /// On the systems, when the theme shows no picture (the fan art behind
    /// is it), the system's video plays there instead.
    private var systemBackdropVideo: URL? {
        let theme = themeStore.current.theme
        guard level == .systems, !theme.systems.showsPicture, playsSystemVideos, theme.systems.playsVideo,
              let section = sections.first(where: { $0.selection == selection }), section.ownArt(.fanart) != nil,
              let url = section.ownArt(.video), GameHeaderMedia.canPlay(url) else { return nil }
        return url
    }

    /// Built when the systems or collections change, not on every redraw:
    /// finding their logos and pictures reads folders, and every press
    /// redraws.
    private var sections: [CabinetSection] { builtSections }

    /// What `sections` depends on, cheap to compare.
    private var sectionsKey: [String] {
        collections.map { "\($0.collectionID)|\($0.name)|\($0.isHidden)|\($0.games.isEmpty)" }
            + systems.map { "\($0.systemID)|\($0.gameCount > 0)" }
            + [emulationFolderStore.folder.root.path]
    }

    /// Library shortcuts first, then non-empty collections, then every
    /// system that actually has games. No All Games: thousands of games in
    /// one shelf made everything slower, and search covers finding one.
    private func buildSections() -> [CabinetSection] {
        [
            CabinetSection(selection: .favorites, title: String(localized: "Favorites")),
            CabinetSection(selection: .recentlyPlayed, title: String(localized: "Recently Played")),
            CabinetSection(selection: .recentlyAdded, title: String(localized: "Recently Added"))
        ] + collections
            .filter { !$0.games.isEmpty && !$0.isHidden }
            .map { collection in
                let root = CollectionFolders.root(in: emulationFolderStore.folder.root)
                let logo = SystemLogoCache.image(at: CollectionFolders.image(named: CollectionFile.logoName, for: collection, root: root))
                    .map { Image(nsImage: $0) }
                return CabinetSection(selection: .collection(collection.collectionID), title: collection.name, logo: logo,
                                      artSource: .collection(CollectionFolders.folderURL(for: collection, root: root)))
            }
        + systems
            .filter { $0.gameCount > 0 }
            .orderedByCategory()
            .map { CabinetSection(selection: .system($0.systemID), title: $0.displayName, logo: $0.logo, artSource: .system($0.romsRootURL)) }
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
        case _ where isSearching:
            searchEvent = newEvent
        case _ where pageGame != nil:
            pageEvent = newEvent
        case _ where level == .systems:
            switch command {
            case .move(.left), .move(.up), .previousSection: stepSection(by: -1)
            case .move(.right), .move(.down), .nextSection: stepSection(by: 1)
            case .activate: setLevel(.games)
            case .random:
                opensRandom = true
                setLevel(.games)
            case .search:
                setLevel(.games)
                isSearching = true
            case .back: exit()
            case .move, .details, .toggleFavorite, .menu, .previousLetter, .nextLetter, .character, .deleteCharacter: break
            }
        case .back:
            // A search or filter clears first, then back to the systems.
            if browse.isFiltered {
                browse.clearFilters()
            } else if themeStore.current.theme.systems.isEnabled {
                setLevel(.systems)
            } else {
                exit()
            }
        case .search:
            isSearching = true
        case .character, .deleteCharacter:
            break
        default:
            event = newEvent
        }
    }

    /// X on a game: its video, facts, description and manual.
    private func showDetails(_ game: Game) {
        focusedGame = game
        pageGame = game
    }

    /// A on a game, or Play on its page.
    private func play(_ game: Game) {
        focusedGame = game
        launchCoordinator.play(game: game, retroArchStore: retroArchStore)
    }

    private func closePage() {
        if let pageGame { focusedGame = pageGame }
        pageGame = nil
    }

    private func showJump(_ label: String) {
        withAnimation(.snappy(duration: 0.15)) { jumpLabel = label }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            if jumpLabel == label { withAnimation(.easeOut(duration: 0.3)) { jumpLabel = nil } }
        }
    }

    /// For the menu's Surprise Me.
    func surprise() {
        send(.random)
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
    /// Where its own pictures and video are.
    var artSource: ArtSource? = nil
    var id: LibrarySelection { selection }

    enum ArtSource {
        /// A system's ROMs folder (see `MediaFolder.SystemArt`).
        case system(URL)
        /// A collection's folder: its fanart, artwork and video files.
        case collection(URL)
    }

    /// The section's own fan art, picture or video.
    func ownArt(_ art: MediaFolder.SystemArt) -> URL? {
        switch artSource {
        case .system(let folder):
            return MediaFolder.systemArt(art, forSystemFolder: folder)
        case .collection(let folder):
            let name = switch art {
            case .logo: CollectionFile.logoName
            case .fanart: CollectionFile.fanartName
            case .picture: CollectionFile.artworkName
            case .video: CollectionFile.videoName
            }
            return CollectionFolders.file(named: name, inFolder: folder)
        case nil:
            return nil
        }
    }

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
    /// The search, filters and order narrowing the games.
    var chips: [String] = []

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

            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(verbatim: chip)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(theme.palette.accent.color.opacity(0.25), in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.palette.accent.color.opacity(0.6)))
                    }
                }
                .font(theme.bodyFont(.medium))
                .fixedSize()
            }

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
    let isFiltered: Bool
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
                hint(gamepad.confirmGlyph, "Open")
                hint(gamepad.glyph(for: .select), "Search")
                hint(gamepad.glyph(for: .r3), "Random")
                hint(gamepad.backGlyph, "Exit")
            case .games:
                hint(gamepad.confirmGlyph, "Play")
                hint(gamepad.glyph(for: .left), "Details")
                hint(gamepad.favoriteGlyph, "Favorite")
                hint(gamepad.glyph(for: .select), "Search")
                hint(gamepad.glyph(for: .r3), "Random")
                hint(gamepad.glyph(for: .l2), "A–Z")
                if isFiltered {
                    hint(gamepad.backGlyph, "Clear")
                } else if backGoesToSystems {
                    hint(gamepad.backGlyph, "Systems")
                } else {
                    hint(gamepad.backGlyph, "Exit")
                }
            }
            Button(action: onMenu) {
                hint(gamepad.menuGlyph, "Menu")
            }
            .buttonStyle(.plain)
        }
        .font(installed.theme.bodyFont())
        .foregroundStyle(installed.theme.palette.secondaryText.color)
    }

    private func hint(_ glyph: ButtonGlyph, _ label: LocalizedStringKey) -> some View {
        Label(label, glyph: glyph)
            .labelStyle(.titleAndIcon)
    }
}

/// The theme's picture, then the focused game's art per the theme —
/// blurred, darkened, cross-fading as focus moves.
private struct CabinetBackdrop: View {
    let game: Game?
    /// Shown without a game.
    var fallback: URL? = nil
    /// Played without a game, already checked against the settings.
    var fallbackVideo: URL? = nil
    var allowsVideo = true

    @Environment(\.cabinetTheme) private var installed
    @State private var image: CGImage?
    @State private var artURL: URL?
    @State private var videoURL: URL?
    @AppStorage(GameHeaderMedia.previewsKey) private var playsPreviews = true
    @AppStorage("videoPreviewsMuted") private var isMuted = true

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
                if let videoURL, allowsVideo {
                    VideoPreviewView(url: videoURL, isMuted: isMuted, fills: true)
                        .blur(radius: backdrop.blur)
                        .opacity(1 - backdrop.dim)
                        .transition(.opacity)
                        .id(videoURL)
                }
            }
            .overlay {
                if backdrop.fade {
                    // Into the background where the details and the row sit.
                    let background = installed.theme.palette.background.color
                    LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: background, location: 0.92)],
                                   startPoint: .top, endPoint: .bottom)
                    LinearGradient(stops: [.init(color: background.opacity(0.9), location: 0), .init(color: background.opacity(0.6), location: 0.32),
                                           .init(color: .clear, location: 0.65)],
                                   startPoint: .leading, endPoint: .trailing)
                    // Under the section names along the top.
                    LinearGradient(stops: [.init(color: background.opacity(0.65), location: 0), .init(color: .clear, location: 0.2)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: artURL)
            .animation(.easeInOut(duration: 0.6), value: videoURL)
            // After a moment on the game, so moving along the row doesn't
            // start a video for every card passed.
            .task(id: [game?.persistentModelID.hashValue.description, String(backdrop.playsVideo), String(playsPreviews), fallbackVideo?.path]) {
                videoURL = nil
                let gameVideo = game.flatMap { game in
                    backdrop.playsVideo && playsPreviews ? game.previewVideoURL.flatMap { GameHeaderMedia.canPlay($0) ? $0 : nil } : nil
                }
                guard let url = gameVideo ?? (game == nil ? fallbackVideo : nil) else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                videoURL = url
            }
            .task(id: [game?.persistentModelID.hashValue.description, fallback?.path, backdrop.source.rawValue, String(backdrop.blur)]) {
                artURL = game.flatMap { CabinetArt.url(for: $0, backdrop.source) } ?? fallback
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
        case .box3D: game.box3DURL ?? game.coverArtURL
        case .screenshot: url(for: game, CabinetTheme.Backdrop.Source.screenshot)
        case .fanart: url(for: game, CabinetTheme.Backdrop.Source.fanart)
        }
    }
}

/// Puts Cabinet Mode's window into native full screen as soon as it appears.
/// The other Attic windows, put away while Cabinet Mode is open: it takes
/// the whole screen, and a library window coming forward (after a game,
/// say) pulled people out of it.
@MainActor
enum CabinetWindows {
    private static var hidden: [NSWindow] = []
    fileprivate static weak var cabinet: NSWindow?

    static func hideOthers() {
        hidden = NSApp.windows.filter { window in
            window.isVisible && window.canBecomeMain && window !== cabinet
                // Cabinet Mode's own, should it not have reported in yet.
                && window.identifier?.rawValue.hasPrefix(CabinetView.windowID) != true
        }
        hidden.forEach { $0.orderOut(nil) }
    }

    static func showOthers() {
        hidden.forEach { $0.makeKeyAndOrderFront(nil) }
        hidden = []
    }

    static func bringCabinetForward() {
        NSApp.activate()
        cabinet?.makeKeyAndOrderFront(nil)
    }
}

private struct FullScreenWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowObservingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowObservingView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            CabinetWindows.cabinet = window
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
