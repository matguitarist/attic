import AppKit
import SwiftUI
import AtticModels

/// The pages of the menu Start opens in Cabinet Mode.
enum CabinetMenuPage: Hashable {
    case main, view, theme, interface, controller, library

    var title: LocalizedStringKey {
        switch self {
        case .main: "Menu"
        case .view: "Sort and Filter"
        case .theme: "Theme"
        case .interface: "Interface"
        case .controller: "Controller"
        case .library: "Library"
        }
    }
}

/// One row of the menu.
struct CabinetMenuItem: Identifiable {
    enum Kind {
        /// Opens another page.
        case page(CabinetMenuPage)
        /// Left and right flip it, as does the confirm button.
        case toggle(Binding<Bool>)
        /// Left and right step through the options; confirm steps forward.
        case choice(options: [String], selection: Binding<Int>, swatches: [Color]? = nil)
        /// Runs on confirm. A confirming action asks for a second press.
        case action(confirm: Bool, perform: () -> Void)
        /// A value to read, never focused.
        case info(String)
    }

    let id: String
    let title: String
    let symbol: String
    let kind: Kind

    var isFocusable: Bool {
        if case .info = kind { return false }
        return true
    }
}

/// The menu Start opens, like EmulationStation's: the theme, how Cabinet
/// Mode behaves, the controller and the library, set from the couch.
/// Styled by the theme's `menu` and palette.
struct CabinetMenuView: View {
    @Binding var path: [CabinetMenuPage]
    let event: CabinetEvent?
    let onExit: () -> Void
    /// Closes the menu and picks a random game, or opens the search.
    let onSurprise: () -> Void
    let onSearch: () -> Void

    @Environment(\.cabinetTheme) private var installed
    @Environment(CabinetBrowse.self) private var browse
    @Environment(CabinetThemeStore.self) private var themeStore
    @Environment(ControllerSettingsStore.self) private var controllerSettings
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @AppStorage(GameHeaderMedia.previewsKey) private var playsVideoPreviews = true
    @AppStorage("videoPreviewsMuted") private var videoPreviewsMuted = true
    @AppStorage(CabinetView.startInCabinetKey) private var startsInCabinet = false
    @AppStorage(CabinetSystemsView.playsVideosKey) private var playsSystemVideos = false

    @State private var focus: [CabinetMenuPage: Int] = [:]
    /// The confirming action waiting for its second press.
    @State private var armedID: String?

    private var page: CabinetMenuPage { path.last ?? .main }

    var body: some View {
        let theme = installed.theme
        let menu = theme.menu
        let items = items(for: page)
        let focused = focusedIndex(in: items)
        ZStack(alignment: alignment(menu.position)) {
            Color.black.opacity(menu.dim)
                .ignoresSafeArea()
                .onTapGesture { path = [] }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    if path.count > 1 {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(theme.palette.secondaryText.color)
                    }
                    Text(page.title)
                        .font(theme.font(size: theme.typography.titleSize * 0.8, weight: .bold))
                        .textCase(theme.typography.uppercase ? .uppercase : nil)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 16)

                // A centered menu is as tall as its rows, scrolling only
                // when they don't fit.
                ViewThatFits(in: .vertical) {
                    if menu.position == .center {
                        rows(items, focused: focused, theme: theme)
                    }
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            rows(items, focused: focused, theme: theme)
                        }
                        .scrollIndicators(.never)
                        .onChange(of: focused) { _, index in
                            if let index, items.indices.contains(index) {
                                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(items[index].id) }
                            }
                        }
                    }
                }

                hints(theme)
                    .padding(20)
            }
            .frame(width: menu.width)
            .frame(maxHeight: menu.position == .center ? nil : .infinity)
            .background(theme.palette.background.color.opacity(0.92))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: menu.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: menu.cornerRadius, style: .continuous)
                    .strokeBorder(theme.palette.accent.color.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 40)
            .padding(menu.position == .center ? 40 : 0)
            .ignoresSafeArea(edges: menu.position == .center ? [] : .vertical)
        }
        .foregroundStyle(theme.palette.text.color)
        .onChange(of: event) { _, newEvent in
            if let newEvent { handle(newEvent.command) }
        }
        .onChange(of: page) { armedID = nil }
    }

    private func alignment(_ position: CabinetTheme.Menu.Position) -> Alignment {
        switch position {
        case .center: .center
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    // MARK: Rows

    private func rows(_ items: [CabinetMenuItem], focused: Int?, theme: CabinetTheme) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, isFocused: index == focused, theme: theme)
                    .id(item.id)
                    .onTapGesture {
                        setFocus(index)
                        activate(item)
                    }
            }
        }
        .padding(.horizontal, 16)
    }

    private func row(_ item: CabinetMenuItem, isFocused: Bool, theme: CabinetTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(6, theme.menu.cornerRadius / 2), style: .continuous)
        let isArmed = armedID == item.id
        return HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .frame(width: 28)
                .foregroundStyle(isFocused ? theme.palette.accent.color : theme.palette.secondaryText.color)
            Text(isArmed ? String(localized: "Press again to confirm") : item.title)
                .lineLimit(1)
            Spacer(minLength: 12)
            value(of: item, isFocused: isFocused, theme: theme)
        }
        .font(theme.largeFont(isFocused ? .semibold : .regular))
        .foregroundStyle(item.isFocusable ? theme.palette.text.color : theme.palette.secondaryText.color)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isFocused ? theme.palette.surface.color : .clear, in: shape)
        .overlay {
            if isFocused {
                shape.strokeBorder(theme.palette.accent.color, lineWidth: 2)
            }
        }
        .contentShape(shape)
        .animation(.snappy(duration: 0.15), value: isFocused)
    }

    @ViewBuilder
    private func value(of item: CabinetMenuItem, isFocused: Bool, theme: CabinetTheme) -> some View {
        let secondary = theme.palette.secondaryText.color
        switch item.kind {
        case .page:
            Image(systemName: "chevron.right")
                .foregroundStyle(secondary)
        case .toggle(let isOn):
            Text(isOn.wrappedValue ? String(localized: "On") : String(localized: "Off"))
                .font(theme.bodyFont(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(isOn.wrappedValue ? theme.palette.accent.color : theme.palette.surface.color, in: Capsule())
                .foregroundStyle(isOn.wrappedValue ? theme.palette.background.color : secondary)
        case .choice(let options, let selection, let swatches):
            HStack(spacing: 10) {
                if isFocused { Image(systemName: "chevron.left").foregroundStyle(secondary) }
                if let swatch = swatches?[safe: selection.wrappedValue] {
                    Circle()
                        .fill(swatch)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4)))
                        .frame(width: 18, height: 18)
                }
                Text(verbatim: options[safe: selection.wrappedValue] ?? "")
                    .lineLimit(1)
                if isFocused { Image(systemName: "chevron.right").foregroundStyle(secondary) }
            }
            .font(theme.bodyFont(.medium))
        case .action:
            EmptyView()
        case .info(let text):
            Text(verbatim: text)
                .font(theme.bodyFont())
                .foregroundStyle(secondary)
                .lineLimit(1)
        }
    }

    private func hints(_ theme: CabinetTheme) -> some View {
        HStack(spacing: 24) {
            Label("Select", glyph: gamepad.confirmGlyph)
            Label("Back", glyph: gamepad.backGlyph)
            Label("Close", glyph: gamepad.menuGlyph)
        }
        .font(theme.bodyFont())
        .foregroundStyle(theme.palette.secondaryText.color)
        .frame(maxWidth: .infinity)
    }

    // MARK: Input

    private func handle(_ command: CabinetEvent.Command) {
        let items = items(for: page)
        guard let index = focusedIndex(in: items) else {
            if command == .back { goBack() }
            return
        }
        switch command {
        case .move(.up): setFocus(step(from: index, by: -1, in: items))
        case .move(.down): setFocus(step(from: index, by: 1, in: items))
        case .move(.left): adjust(items[index], by: -1)
        case .move(.right): adjust(items[index], by: 1)
        case .activate: activate(items[index])
        case .back: goBack()
        default: break
        }
    }

    private func focusedIndex(in items: [CabinetMenuItem]) -> Int? {
        let stored = focus[page] ?? 0
        if items.indices.contains(stored), items[stored].isFocusable { return stored }
        return items.firstIndex(where: \.isFocusable)
    }

    private func setFocus(_ index: Int) {
        if focus[page] != index { armedID = nil }
        focus[page] = index
    }

    /// The next focusable row, wrapping around.
    private func step(from index: Int, by offset: Int, in items: [CabinetMenuItem]) -> Int {
        var next = index
        for _ in items.indices {
            next = (next + offset + items.count) % items.count
            if items[next].isFocusable { return next }
        }
        return index
    }

    private func adjust(_ item: CabinetMenuItem, by offset: Int) {
        switch item.kind {
        case .toggle(let isOn): isOn.wrappedValue.toggle()
        case .choice(let options, let selection, _) where !options.isEmpty:
            selection.wrappedValue = (selection.wrappedValue + offset + options.count) % options.count
        case .page(let target) where offset > 0: open(target)
        case .page, .choice, .action, .info:
            if offset < 0 { goBack() }
        }
    }

    private func activate(_ item: CabinetMenuItem) {
        switch item.kind {
        case .page(let target): open(target)
        case .toggle, .choice: adjust(item, by: 1)
        case .action(let confirm, let perform):
            if confirm && armedID != item.id {
                armedID = item.id
            } else {
                armedID = nil
                perform()
            }
        case .info: break
        }
    }

    private func open(_ target: CabinetMenuPage) {
        withAnimation(.snappy(duration: 0.2)) { path.append(target) }
    }

    private func goBack() {
        withAnimation(.snappy(duration: 0.2)) { _ = path.popLast() }
    }

    // MARK: Pages

    private func items(for page: CabinetMenuPage) -> [CabinetMenuItem] {
        switch page {
        case .main: mainItems
        case .view: viewItems
        case .theme: themeItems
        case .interface: interfaceItems
        case .controller: controllerItems
        case .library: libraryItems
        }
    }

    private var mainItems: [CabinetMenuItem] {
        [
            CabinetMenuItem(id: "surprise", title: String(localized: "Surprise Me"), symbol: "dice",
                            kind: .action(confirm: false, perform: onSurprise)),
            CabinetMenuItem(id: "search", title: String(localized: "Search"), symbol: "magnifyingglass",
                            kind: .action(confirm: false, perform: onSearch)),
            CabinetMenuItem(id: "view", title: String(localized: "Sort and Filter"), symbol: "line.3.horizontal.decrease.circle", kind: .page(.view)),
            CabinetMenuItem(id: "theme", title: String(localized: "Theme"), symbol: "paintpalette", kind: .page(.theme)),
            CabinetMenuItem(id: "interface", title: String(localized: "Interface"), symbol: "rectangle.on.rectangle", kind: .page(.interface)),
            CabinetMenuItem(id: "controller", title: String(localized: "Controller"), symbol: gamepad.controllerSymbol, kind: .page(.controller)),
            CabinetMenuItem(id: "library", title: String(localized: "Library"), symbol: "books.vertical", kind: .page(.library)),
            CabinetMenuItem(id: "exit", title: String(localized: "Exit Cabinet Mode"), symbol: "rectangle.portrait.and.arrow.right",
                            kind: .action(confirm: false, perform: onExit)),
            CabinetMenuItem(id: "quit", title: String(localized: "Quit Attic"), symbol: "power",
                            kind: .action(confirm: true, perform: { NSApp.terminate(nil) }))
        ]
    }

    private var themeItems: [CabinetMenuItem] {
        let themes = themeStore.themes
        let current = themeStore.current
        let layouts = CabinetTheme.Layout.allCases
        let arts = CabinetTheme.Tiles.Art.allCases
        let sides = CabinetTheme.Details.Side.allCases
        // The theme's own accent first, then the presets.
        let original = themes.first { $0.id == current.id }?.theme.palette.accent ?? current.theme.palette.accent
        let accents = [original] + CabinetTheme.accentPresets.map(\.color)
        var items = [
            CabinetMenuItem(id: "theme", title: String(localized: "Theme"), symbol: "paintpalette",
                            kind: .choice(options: themes.map(\.theme.name), selection: Binding(
                                get: { themes.firstIndex { $0.id == themeStore.selectedID } ?? 0 },
                                set: { if themes.indices.contains($0) { themeStore.selectedID = themes[$0].id } }
                            ))),
            CabinetMenuItem(id: "layout", title: String(localized: "Layout"), symbol: "square.grid.2x2",
                            kind: .choice(options: layouts.map(\.title), selection: Binding(
                                get: { layouts.firstIndex(of: current.theme.layout) ?? 0 },
                                set: { themeStore.adjust("layout", to: layouts[$0].rawValue) }
                            ))),
            CabinetMenuItem(id: "art", title: String(localized: "Game Art"), symbol: "photo.on.rectangle",
                            kind: .choice(options: arts.map(\.title), selection: Binding(
                                get: { arts.firstIndex(of: current.theme.tiles.art) ?? 0 },
                                set: { themeStore.adjust("tiles.art", to: arts[$0].rawValue) }
                            ))),
            CabinetMenuItem(id: "side", title: String(localized: "Details Side"), symbol: "sidebar.left",
                            kind: .choice(options: sides.map(\.title), selection: Binding(
                                get: { sides.firstIndex(of: current.theme.details.side) ?? 0 },
                                set: { themeStore.adjust("details.side", to: sides[$0].rawValue) }
                            ))),
            CabinetMenuItem(id: "accent", title: String(localized: "Accent Color"), symbol: "paintbrush",
                            kind: .choice(options: [String(localized: "Theme's")] + CabinetTheme.accentPresets.map(\.name), selection: Binding(
                                get: { accents.dropFirst().firstIndex(of: current.theme.palette.accent) ?? 0 },
                                set: { themeStore.adjust("palette.accent", to: $0 == 0 ? nil : accents[$0].hex) }
                            ), swatches: accents.map(\.color)))
        ]
        if current.isAdjusted {
            items.append(CabinetMenuItem(id: "reset", title: String(localized: "Back to the Theme's Own"), symbol: "arrow.uturn.backward",
                                         kind: .action(confirm: false, perform: { themeStore.resetAdjustments() })))
        }
        items += [
            CabinetMenuItem(id: "author", title: String(localized: "By"), symbol: "person",
                            kind: .info(current.theme.author ?? (current.isBuiltIn ? "Attic" : String(localized: "You")))),
            CabinetMenuItem(id: "reload", title: String(localized: "Reload Themes"), symbol: "arrow.clockwise",
                            kind: .action(confirm: false, perform: { themeStore.reload() }))
        ]
        return items
    }

    private var viewItems: [CabinetMenuItem] {
        @Bindable var browse = browse
        let sorts = CabinetSort.allCases
        let players = [0, 2, 4]
        let genres = [("", String(localized: "Any"))] + CabinetBrowse.genres.map { ($0.terms, $0.name) }
        var items = [
            CabinetMenuItem(id: "sort", title: String(localized: "Order"), symbol: "arrow.up.arrow.down",
                            kind: .choice(options: sorts.map(\.title), selection: Binding(
                                get: { sorts.firstIndex(of: browse.sort) ?? 0 },
                                set: { browse.sort = sorts[$0] }
                            ))),
            CabinetMenuItem(id: "favorites", title: String(localized: "Favorites only"), symbol: "star",
                            kind: .toggle($browse.favoritesOnly)),
            CabinetMenuItem(id: "players", title: String(localized: "Players"), symbol: "person.2",
                            kind: .choice(options: [String(localized: "Any"), String(localized: "2 or more"), String(localized: "4 or more")],
                                          selection: Binding(
                                            get: { players.firstIndex(of: browse.minPlayers) ?? 0 },
                                            set: { browse.minPlayers = players[$0] }
                                          ))),
            CabinetMenuItem(id: "genre", title: String(localized: "Genre"), symbol: "tag",
                            kind: .choice(options: genres.map(\.1), selection: Binding(
                                get: { genres.firstIndex { $0.0 == browse.genre } ?? 0 },
                                set: { browse.genre = genres[$0].0 }
                            )))
        ]
        if browse.isFiltered {
            items.append(CabinetMenuItem(id: "clear", title: String(localized: "Clear Search and Filters"), symbol: "xmark.circle",
                                         kind: .action(confirm: false, perform: { browse.clearFilters() })))
        }
        return items
    }

    private var interfaceItems: [CabinetMenuItem] {
        [
            CabinetMenuItem(id: "videos", title: String(localized: "Play videos"), symbol: "play.rectangle",
                            kind: .toggle($playsVideoPreviews)),
            CabinetMenuItem(id: "systemVideos", title: String(localized: "System videos"), symbol: "film",
                            kind: .toggle($playsSystemVideos)),
            CabinetMenuItem(id: "sound", title: String(localized: "Video sound"), symbol: "speaker.wave.2",
                            kind: .toggle(Binding(get: { !videoPreviewsMuted }, set: { videoPreviewsMuted = !$0 }))),
            CabinetMenuItem(id: "start", title: String(localized: "Open Cabinet Mode at launch"), symbol: "play.tv",
                            kind: .toggle($startsInCabinet))
        ]
    }

    private var controllerItems: [CabinetMenuItem] {
        @Bindable var controllerSettings = controllerSettings
        var items = [
            CabinetMenuItem(id: "pad", title: String(localized: "Connected"), symbol: gamepad.controllerSymbol,
                            kind: .info(gamepad.connectedControllerName ?? String(localized: "None"))),
            CabinetMenuItem(id: "icons", title: String(localized: "Button Icons"), symbol: gamepad.favoriteButtonSymbol,
                            kind: .choice(options: [String(localized: "Automatic")] + ControllerFamily.allCases.map(\.title),
                                          selection: Binding(
                                            get: { gamepad.buttonIcons.flatMap { ControllerFamily.allCases.firstIndex(of: $0).map { $0 + 1 } } ?? 0 },
                                            set: { gamepad.buttonIcons = $0 == 0 ? nil : ControllerFamily.allCases[$0 - 1] }
                                          ))),
            CabinetMenuItem(id: "layout", title: String(localized: "Confirm Button"), symbol: gamepad.confirmButtonSymbol,
                            kind: .choice(options: [String(localized: "Bottom — Xbox, PlayStation"), String(localized: "Right — Nintendo, Switch")],
                                          selection: Binding(
                                            get: { controllerSettings.settings.layout == .classic ? 0 : 1 },
                                            set: { controllerSettings.settings.layout = $0 == 0 ? .classic : .nintendo }
                                          ))),
            CabinetMenuItem(id: "stick", title: String(localized: "Left stick also works as the D-pad"), symbol: "l.joystick",
                            kind: .toggle($controllerSettings.settings.leftStickAsDPad)),
            CabinetMenuItem(id: "quit", title: String(localized: "Quit games with Select + Start"), symbol: "xmark.circle",
                            kind: .toggle($controllerSettings.settings.quitWithSelectStart)),
            CabinetMenuItem(id: "pause", title: String(localized: "Game menu"), symbol: "pause.circle",
                            kind: .choice(options: PauseMenuCombo.allCases.map(\.title), selection: Binding(
                                get: { PauseMenuCombo.allCases.firstIndex(of: controllerSettings.settings.pauseMenu) ?? 0 },
                                set: { controllerSettings.settings.pauseMenu = PauseMenuCombo.allCases[$0] }
                            )))
        ]
        let profiles = controllerSettings.savedProfiles
        if !profiles.isEmpty {
            let custom = String(localized: "Custom")
            items.append(CabinetMenuItem(id: "profile", title: String(localized: "Profile"), symbol: "person.crop.rectangle.stack",
                                         kind: .choice(options: profiles.map(\.name) + [custom], selection: Binding(
                                            get: { controllerSettings.matchingProfile.flatMap { match in profiles.firstIndex { $0.id == match.id } } ?? profiles.count },
                                            set: { if profiles.indices.contains($0) { controllerSettings.apply(profiles[$0]) } }
                                         ))))
        }
        return items
    }

    private var libraryItems: [CabinetMenuItem] {
        let isScanning = scanCoordinator.state == .scanning
        return [
            CabinetMenuItem(id: "rescan", title: isScanning ? String(localized: "Scanning…") : String(localized: "Rescan Library"),
                            symbol: "arrow.triangle.2.circlepath",
                            kind: .action(confirm: false, perform: {
                                guard !isScanning else { return }
                                Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
                            })),
            CabinetMenuItem(id: "summary", title: String(localized: "Last scan"), symbol: "info.circle",
                            kind: .info(scanCoordinator.lastScanSummary ?? "—"))
        ]
    }
}
