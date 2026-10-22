import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import AtticPersistence
import AtticModels

/// Native macOS layout throughout: a `NavigationSplitView` sidebar, the
/// window's own toolbar (title, search, sort, zoom, scrape), and an
/// `.inspector` for game details — so the OS draws all the chrome and it
/// keeps up with each release's look instead of us re-skinning it by hand.
struct LibraryBrowserView: View {
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @AppStorage(LibrarySidebarView.hideEmptySystemsKey) private var hidesEmptySystems = false
    @State private var selection: LibrarySelection? = .allGames
    @State private var searchText = ""
    @State private var sortOrder: GameSortOrder = .title
    /// Collections keep their own order, by system then release date
    /// unless changed, so a series reads in order.
    @AppStorage("collectionSortOrder") private var collectionSortOrder = GameSortOrder.systemThenRelease
    @State private var selectedGame: Game?
    @State private var multiSelection: [Game] = []
    /// Bumped to have the grid pick a game at random.
    @State private var randomPicks = 0
    @AppStorage("gridCellScale") private var cellScale: Double = 1.0
    @AppStorage("showsGameInspector") private var showsInspector = true
    @State private var showsControllerHelp = false
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(\.openWindow) private var openWindow
    @AppStorage(CabinetView.startInCabinetKey) private var startsInCabinet = false
    /// Once per launch — not every time a library window appears.
    private static var didAutoOpenCabinet = false

    @State private var infoEditor = GameInfoEditor()
    @State private var collectionCoordinator = CollectionCoordinator()
    @State private var systemSettingsEditor = SystemSettingsEditor()
    @State private var romImporter = ROMImportCoordinator()
    @State private var importSummary: String?
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(\.modelContext) private var modelContext
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Query(sort: \GameCollection.name) private var collections: [GameCollection]

    static let cellScaleRange: ClosedRange<Double> = 0.6...1.8

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(systems: shownSystems, collections: collections.filter { !$0.isHidden }, selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            GameGridView(
                selection: currentSelection,
                searchText: searchText,
                sortOrder: shownSortOrder.wrappedValue,
                cellScale: CGFloat(cellScale),
                selectedGame: $selectedGame,
                multiSelection: $multiSelection,
                randomPicks: randomPicks
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    ROMImportStatusBar(importer: romImporter)
                    ToolsStatusBar()
                    BatchScrapeStatusBar()
                }
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 460, ideal: 800)
            .navigationTitle(selectionTitle)
            .toolbar { toolbarContent }
            // Games dropped here go to the system shown when it takes
            // them, else to the one their file type says.
            .dropDestination(for: URL.self) { urls, _ in
                importROMs(urls, shown: selectedSystem?.systemID)
                return true
            }
        }
        // In the sidebar rather than the toolbar: a toolbar search field
        // always goes last, which puts it over the inspector column. Before
        // `.inspector`, or it lands in the inspector's toolbar.
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search Games")
        // On the split view rather than its detail column, so the inspector
        // is a column of its own with its own part of the toolbar; inside
        // the detail column, the grid's toolbar items ran on over it.
        .inspector(isPresented: $showsInspector) {
            Group {
                if multiSelection.count > 1 {
                    MultipleGamesSummaryView(games: multiSelection)
                } else {
                    GameDetailView(game: selectedGame, system: selectedSystem, collection: shownCollection)
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 480)
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem { inspectorToggle }
            }
        }
        .focusedSceneValue(\.selectedGame, selectedGame)
        .focusedSceneValue(\.addGames, MenuAction { chooseGamesToAdd() })
        .focusedSceneValue(\.editCollection, shownCollection.map { collection in MenuAction { collectionCoordinator.edit(collection) } })
        .focusedSceneValue(\.exportCollection, shownCollection.map { collection in MenuAction { CollectionFolders.export(collection, root: collectionsRoot) } })
        .focusedSceneValue(\.importCollection, MenuAction { chooseCollectionToImport() })
        .alert("Collection Imported", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
            Button("OK") { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
        .focusedSceneValue(\.gameInfoEditor, infoEditor)
        .environment(infoEditor)
        .focusedSceneValue(\.collectionCoordinator, collectionCoordinator)
        .environment(collectionCoordinator)
        .sheet(item: $collectionCoordinator.draft) { draft in
            CollectionEditorView(draft: draft) { created in
                // A collection made from the sidebar starts empty unless it
                // picked up matching games — show it either way.
                if case .new(let games) = draft.mode, games.isEmpty {
                    selection = .collection(created.collectionID)
                }
            }
        }
        .confirmationDialog(
            "Delete “\(collectionCoordinator.pendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { collectionCoordinator.pendingDeletion != nil },
                set: { if !$0 { collectionCoordinator.pendingDeletion = nil } }
            ),
            presenting: collectionCoordinator.pendingDeletion
        ) { collection in
            Button("Delete Collection", role: .destructive) {
                if selection == .collection(collection.collectionID) { selection = .allGames }
                CollectionFolders.remove(collection, root: collectionsRoot)
                let context = collection.modelContext
                context?.delete(collection)
                try? context?.save()
            }
        } message: { _ in
            Text("The games stay in your library. The collection's folder, with its pictures, goes to the Trash.")
        }
        .sheet(item: $infoEditor.game) { game in
            EditGameInfoView(game: game)
        }
        .environment(systemSettingsEditor)
        .environment(\.importROMs, ImportROMsAction { urls, system in importROMs(urls, into: system) })
        .sheet(item: Binding(get: { romImporter.question }, set: { _ in })) { question in
            ROMImportSheet(question: question) { romImporter.answer($0) }
        }
        .alert("Games Added", isPresented: Binding(get: { romImporter.summary != nil }, set: { if !$0 { romImporter.summary = nil } })) {
            Button("OK") { romImporter.summary = nil }
        } message: {
            Text(romImporter.summary ?? "")
        }
        .sheet(item: $systemSettingsEditor.system) { system in
            SystemSettingsView(system: system)
        }
        .toolsReports(in: .library)
        // A selection belongs to what was showing when it was made; the
        // newly shown system's overview takes its place.
        .onChange(of: selection) {
            multiSelection = []
            selectedGame = nil
        }
        .onChange(of: searchText) { multiSelection = [] }
        // A removed (or now hidden) system's page goes with it.
        .onChange(of: shownSystems.map(\.systemID)) { _, ids in
            if case .system(let id) = currentSelection, !ids.contains(id) {
                selection = .allGames
            }
        }
        .missingBIOSAlert(isActive: !gamepad.isCabinetActive)
        .failedLaunchAlert(isActive: !gamepad.isCabinetActive)
        .onAppear {
            if startsInCabinet, !Self.didAutoOpenCabinet {
                Self.didAutoOpenCabinet = true
                openWindow(id: CabinetView.windowID)
            }
        }
        .onChange(of: gamepad.lastEvent) { _, event in
            guard !gamepad.isCabinetActive else { return }
            switch event?.command {
            case .previousSection: stepSection(by: -1)
            case .nextSection: stepSection(by: 1)
            case .toggleCabinet: openWindow(id: CabinetView.windowID)
            default: break
            }
        }
    }

    private var currentSelection: LibrarySelection { selection ?? .allGames }

    /// The sort the toolbar shows and changes: the collections' own while
    /// one is shown.
    private var shownSortOrder: Binding<GameSortOrder> {
        if case .collection = currentSelection { $collectionSortOrder } else { $sortOrder }
    }

    /// The collection shown, when the sidebar selection is one.
    private var shownCollection: GameCollection? {
        guard case .collection(let id) = currentSelection else { return nil }
        return collections.first { $0.collectionID == id }
    }

    private var collectionsRoot: URL { CollectionFolders.root(in: emulationFolderStore.folder.root) }

    /// File › Import Collection…: a collection folder someone exported, or
    /// its collection.json.
    private func chooseCollectionToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json, .folder] + [UTType(filenameExtension: "cfg")].compactMap { $0 }
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose an exported collection folder or its collection.json, or ES-DE custom collections (custom-Name.cfg, in ES-DE's collections folder).")
        panel.directoryURL = Self.esdeCollectionsFolder
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { importCollection(from: url) }
        }
    }

    /// ES-DE's custom collections, when it's been used here.
    private static var esdeCollectionsFolder: URL? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "ES-DE/collections", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    /// Imports the collection folder (or collection.json) at `url`, and
    /// shows it.
    private func importCollection(from url: URL) {
        guard let result = CollectionFolders.importCollection(from: url, context: modelContext, root: collectionsRoot) else {
            importSummary = String(localized: "That isn't a collection Attic can read.")
            return
        }
        selection = .collection(result.collection.collectionID)
        importSummary = result.missing == 0
            ? String(localized: "“\(result.collection.name)” has all \(result.found) of its games.")
            : String(localized: "“\(result.collection.name)” has \(result.found) games; \(result.missing) aren't in your library.")
    }

    /// File › Add Games…: the same import as dropping them on the window.
    private func chooseGamesToAdd() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose games, or folders of games. They're filed in your ROMs folder with their covers and videos.")
        panel.begin { response in
            guard response == .OK else { return }
            importROMs(panel.urls, shown: selectedSystem?.systemID)
        }
    }

    private func importROMs(_ urls: [URL], into system: CanonicalSystemID? = nil, shown: CanonicalSystemID? = nil) {
        // Exported collections dropped with (or instead of) games are
        // imported as collections.
        let collections = urls.filter(CollectionFolders.isCollection)
        for url in collections { importCollection(from: url) }
        let urls = urls.filter { !CollectionFolders.isCollection($0) }
        guard !urls.isEmpty else { return }
        romImporter.receive(urls, into: system, shown: shown, romsRoots: romsRootsStore.rootURLs, emulationFolder: emulationFolderStore.folder) {
            Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
        }
    }

    /// The sidebar's systems: all, or only those with games.
    private var shownSystems: [GameSystem] {
        hidesEmptySystems ? systems.filter { $0.gameCount > 0 } : systems
    }

    /// The system shown, when the sidebar selection is one.
    private var selectedSystem: GameSystem? {
        guard case .system(let id) = currentSelection else { return nil }
        return systems.first { $0.systemID == id }
    }


    private var inspectorToggle: some View {
        Button {
            showsInspector.toggle()
        } label: {
            Label("Inspector", systemImage: "info.circle")
        }
        .help(showsInspector ? String(localized: "Hide the inspector") : String(localized: "Show the inspector"))
    }

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
                Picker("Sort By", selection: shownSortOrder) {
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

        if let collection = shownCollection {
            ToolbarItem {
                Button {
                    collectionCoordinator.edit(collection)
                } label: {
                    Label("Edit Collection", systemImage: "slider.horizontal.3")
                }
                .help("Rename this collection, change its search or add and remove games")
            }
        }

        ToolbarItem {
            Button {
                randomPicks += 1
            } label: {
                Label("Random Game", systemImage: "dice")
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .help("Pick a game at random from the ones shown (⌥⌘R)")
        }

        ToolbarItem {
            ScrapeMissingButton(selection: currentSelection)
        }

        ToolbarItem {
            if scanCoordinator.state == .scanning {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 8)
                    .help("Refreshing the library…")
            } else {
                Button {
                    Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
                } label: {
                    Label("Refresh Library", systemImage: "arrow.clockwise")
                }
                .disabled(romsRootsStore.rootURLs.isEmpty)
                .help("Look for games added to or removed from your ROMs folder (⌘R)")
            }
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

        ToolbarItemGroup {
            Button {
                openWindow(id: LogView.windowID)
            } label: {
                Label("Log", systemImage: "list.bullet.rectangle")
            }
            .help("What Attic did and what emulators said, to see why a game won't start (⌥⌘L)")

            Button {
                openWindow(id: CabinetView.windowID)
            } label: {
                Label("Cabinet Mode", systemImage: "tv")
            }
            .help("Full-screen couch mode (⌘⇧B, or Menu/Start on a controller)")
        }

        // The inspector toggle is in the inspector's own toolbar (see
        // `.inspector` above), which stays in place while it's closed.
    }

    /// Same order the sidebar lists them in, wrapping at either end so a
    /// shoulder button can cycle through everything without a dead stop.
    private func stepSection(by offset: Int) {
        let sections: [LibrarySelection] = [.allGames, .favorites, .recentlyPlayed, .recentlyAdded]
            + collections.map { .collection($0.collectionID) }
            + shownSystems.orderedByCategory().map { .system($0.systemID) }
        let currentIndex = sections.firstIndex(of: currentSelection) ?? 0
        let count = sections.count
        selection = sections[((currentIndex + offset) % count + count) % count]
    }

    private var selectionTitle: String {
        switch currentSelection {
        case .allGames: String(localized: "All Games")
        case .favorites: String(localized: "Favorites")
        case .recentlyPlayed: String(localized: "Recently Played")
        case .recentlyAdded: String(localized: "Recently Added")
        case .system(let canonicalID):
            systems.first { $0.systemID == canonicalID }?.displayName ?? canonicalID.rawValue
        case .collection(let collectionID):
            collections.first { $0.collectionID == collectionID }?.name ?? String(localized: "Collection")
        }
    }
}

/// What each controller button does in the library — shown from the
/// toolbar's controller button.
private struct ControllerHelpView: View {
    let controllerName: String
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(ControllerSettingsStore.self) private var controllerSettings

    var body: some View {
        let _ = controllerSettings.settings.layout
        VStack(alignment: .leading, spacing: 12) {
            Label(controllerName, systemImage: "gamecontroller.fill")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row(Text("D-pad / Left Stick"), "Browse games")
                row(Text(Image(systemName: gamepad.confirmButtonSymbol)), "Play")
                row(Text(Image(systemName: gamepad.backButtonSymbol)), "Exit Cabinet Mode")
                row(Text(Image(systemName: gamepad.favoriteButtonSymbol)), "Add to / remove from Favorites")
                row(Text("LB / RB"), "Previous / next system")
                row(Text("Menu / Start"), "Cabinet Mode (full screen)")
            }
            .font(.callout)
        }
        .padding()
    }

    private func row(_ control: Text, _ action: LocalizedStringKey) -> some View {
        GridRow {
            control.foregroundStyle(.secondary)
            Text(action)
        }
    }
}
