import SwiftUI
import SwiftData
import RomsBoxPersistence

/// Native macOS layout throughout: a `NavigationSplitView` sidebar, the
/// window's own toolbar (title, search, sort, zoom, scrape), and an
/// `.inspector` for game details — so the OS draws all the chrome and it
/// keeps up with each release's look instead of us re-skinning it by hand.
struct LibraryBrowserView: View {
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @State private var selection: LibrarySelection? = .allGames
    @State private var searchText = ""
    @State private var sortOrder: GameSortOrder = .title
    @State private var selectedGame: Game?
    @AppStorage("gridCellScale") private var cellScale: Double = 1.0
    @AppStorage("showsGameInspector") private var showsInspector = true
    @State private var showsControllerHelp = false
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(\.openWindow) private var openWindow
    @AppStorage(BigBoxView.startInBigBoxKey) private var startsInBigBox = false
    /// Once per launch — not every time a library window appears.
    private static var didAutoOpenBigBox = false

    static let cellScaleRange: ClosedRange<Double> = 0.6...1.8

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(systems: systems, selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            GameGridView(
                selection: currentSelection,
                searchText: searchText,
                sortOrder: sortOrder,
                cellScale: CGFloat(cellScale),
                selectedGame: $selectedGame
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BatchScrapeStatusBar()
                    .background(.bar)
            }
            .navigationTitle(selectionTitle)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search Games")
            .toolbar { toolbarContent }
            .inspector(isPresented: $showsInspector) {
                GameDetailView(game: selectedGame)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 480)
            }
        }
        .focusedSceneValue(\.selectedGame, selectedGame)
        .onAppear {
            if startsInBigBox, !Self.didAutoOpenBigBox {
                Self.didAutoOpenBigBox = true
                openWindow(id: BigBoxView.windowID)
            }
        }
        .onChange(of: gamepad.lastEvent) { _, event in
            guard !gamepad.isBigBoxActive else { return }
            switch event?.command {
            case .previousSection: stepSection(by: -1)
            case .nextSection: stepSection(by: 1)
            case .toggleBigBox: openWindow(id: BigBoxView.windowID)
            default: break
            }
        }
    }

    private var currentSelection: LibrarySelection { selection ?? .allGames }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Slider(value: $cellScale, in: Self.cellScaleRange) {
                Text("Cover Size")
            } minimumValueLabel: {
                Image(systemName: "photo").imageScale(.small)
            } maximumValueLabel: {
                Image(systemName: "photo").imageScale(.large)
            }
            .labelsHidden()
            .frame(width: 140)
            // A custom view gets no inset of its own inside the toolbar's
            // glass capsule (unlike buttons), so without this the small/
            // large picture labels sit flush against its rounded ends.
            .padding(.horizontal, 8)
            .help("Cover art size")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Menu {
                Picker("Sort By", selection: $sortOrder) {
                    ForEach(GameSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort by")
        }

        ToolbarItem {
            ScrapeMissingButton(selection: currentSelection)
        }

        ToolbarSpacer(.fixed)

        // A real Button (not a bare Image) so it gets the same padding and
        // hit target as every other toolbar item — and clicking it explains
        // the controls instead of just sitting there as a status glyph.
        if let controllerName = gamepad.connectedControllerName {
            ToolbarItem {
                Button {
                    showsControllerHelp.toggle()
                } label: {
                    Label("Controller", systemImage: "gamecontroller.fill")
                }
                .help("\(controllerName) connected")
                .popover(isPresented: $showsControllerHelp, arrowEdge: .bottom) {
                    ControllerHelpView(controllerName: controllerName)
                }
            }
        }

        ToolbarItem {
            Button {
                openWindow(id: BigBoxView.windowID)
            } label: {
                Label("Big Box", systemImage: "tv")
            }
            .help("Full-screen couch mode (⌘⇧B, or Menu/Start on a controller)")
        }

        ToolbarItem {
            Button {
                showsInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "info.circle")
            }
            .help(showsInspector ? String(localized: "Hide game details") : String(localized: "Show game details"))
        }
    }

    /// Same order the sidebar lists them in, wrapping at either end so a
    /// shoulder button can cycle through everything without a dead stop.
    private func stepSection(by offset: Int) {
        let sections: [LibrarySelection] = [.allGames, .favorites, .recentlyPlayed] + systems.map { .system($0.systemID) }
        let currentIndex = sections.firstIndex(of: currentSelection) ?? 0
        let count = sections.count
        selection = sections[((currentIndex + offset) % count + count) % count]
    }

    private var selectionTitle: String {
        switch currentSelection {
        case .allGames: String(localized: "All Games")
        case .favorites: String(localized: "Favorites")
        case .recentlyPlayed: String(localized: "Recently Played")
        case .system(let canonicalID):
            systems.first { $0.systemID == canonicalID }?.displayName ?? canonicalID.rawValue
        }
    }
}

/// What each controller button does in the library — shown from the
/// toolbar's controller button.
private struct ControllerHelpView: View {
    let controllerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(controllerName, systemImage: "gamecontroller.fill")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("D-pad / Left Stick", "Browse games")
                row("A", "Play")
                row("Y", "Add to / remove from Favorites")
                row("LB / RB", "Previous / next system")
                row("Menu / Start", "Big Box (full-screen mode)")
            }
            .font(.callout)
        }
        .padding()
    }

    private func row(_ control: LocalizedStringKey, _ action: LocalizedStringKey) -> some View {
        GridRow {
            Text(control).foregroundStyle(.secondary)
            Text(action)
        }
    }
}
