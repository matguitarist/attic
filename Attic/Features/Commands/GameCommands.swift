import SwiftUI
import AtticModels
import AtticPersistence

extension FocusedValues {
    /// The library window's currently selected game, published with
    /// `.focusedSceneValue` so menu bar commands act on it.
    @Entry var selectedGame: Game?
    /// File › Add Games…, from the library window (which shows the
    /// import's questions and progress).
    @Entry var addGames: MenuAction?
    /// File › Edit Collection… and Export Collection…, while a collection
    /// is shown.
    @Entry var editCollection: MenuAction?
    @Entry var exportCollection: MenuAction?
    @Entry var importCollection: MenuAction?
}

/// A menu bar action a window publishes for the commands to call.
struct MenuAction {
    let run: () -> Void
    func callAsFunction() { run() }
}

/// The File menu: adding games and keeping the library in step with the
/// ROMs folder. Replaces SwiftUI's New Window, since Attic has one library
/// window (a second one crashed).
struct LibraryCommands: Commands {
    let scanCoordinator: ScanCoordinator
    let romsRootsStore: RomsRootsStore

    @FocusedValue(\.addGames) private var addGames
    @FocusedValue(\.editCollection) private var editCollection
    @FocusedValue(\.exportCollection) private var exportCollection
    @FocusedValue(\.importCollection) private var importCollection
    @FocusedValue(\.collectionCoordinator) private var collectionCoordinator
    @AppStorage(RemovedSystems.key) private var removedSystems = ""

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Games…") { addGames?() }
                .keyboardShortcut("o")
                .disabled(addGames == nil || romsRootsStore.rootURLs.isEmpty)

            Button("New Collection…") {
                collectionCoordinator?.newCollection()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(collectionCoordinator == nil)

            Button("Edit Collection…") { editCollection?() }
                .disabled(editCollection == nil)
            Button("Import Collection…") { importCollection?() }
                .disabled(importCollection == nil)
            Button("Export Collection…") { exportCollection?() }
                .disabled(exportCollection == nil)

            Divider()

            Button("Refresh Library") { refresh() }
                .keyboardShortcut("r")
                .disabled(romsRootsStore.rootURLs.isEmpty || scanCoordinator.state == .scanning)

            Button("Show ROMs Folder") {
                if let root = romsRootsStore.rootURLs.first { NSWorkspace.shared.open(root) }
            }
            .disabled(romsRootsStore.rootURLs.isEmpty)

            // Reads `removedSystems` so it updates when one is removed.
            if !removedSystems.isEmpty {
                Menu("Add Back Removed System") {
                    ForEach(RemovedSystems.ids, id: \.self) { id in
                        Button(SystemTaxonomy.definition(for: id)?.displayName ?? id.rawValue) {
                            RemovedSystems.addBack(id)
                            refresh()
                        }
                    }
                }
            }
        }
    }

    private func refresh() {
        Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
    }
}

/// The menu bar's Game menu. Gives every per-game action a standard
/// keyboard shortcut and a discoverable home, the way native Mac apps do,
/// instead of living only in context menus and inspector buttons.
struct GameCommands: Commands {
    let launchCoordinator: LaunchCoordinator
    let retroArchStore: RetroArchSettingsStore

    @FocusedValue(\.selectedGame) private var game
    @FocusedValue(\.gameInfoEditor) private var infoEditor
    @FocusedValue(\.collectionCoordinator) private var collectionCoordinator

    var body: some Commands {
        CommandMenu("Game") {
            Button("Play") {
                if let game { launchCoordinator.play(game: game, retroArchStore: retroArchStore) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(game == nil)

            Button(game?.favorite == true ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) {
                guard let game else { return }
                game.favorite.toggle()
                try? game.modelContext?.save()
            }
            .keyboardShortcut("d")
            .disabled(game == nil)

            Button("Edit Info…") {
                infoEditor?.game = game
            }
            .keyboardShortcut("i")

            Button("Add to New Collection…") {
                if let game { collectionCoordinator?.newCollection(with: [game]) }
            }
            .disabled(game == nil || collectionCoordinator == nil)
            .disabled(game == nil || infoEditor == nil)

            Button("Open Manual") {
                if let manual = game?.manualURL { NSWorkspace.shared.open(manual) }
            }
            .disabled(game?.manualURL == nil)

            Divider()

            Button("Reveal in Finder") {
                if let game { NSWorkspace.shared.activateFileViewerSelecting([game.romAbsoluteURL]) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(game == nil)
        }
    }
}

/// The Tools menu: looking after the ROMs folders (tidying, compressing),
/// the selected game's files, and what Attic keeps on the side.
struct ToolsCommands: Commands {
    let tools: ToolsCoordinator
    let scanCoordinator: ScanCoordinator
    let romsRootsStore: RomsRootsStore
    let emulationFolderStore: EmulationFolderStore

    @FocusedValue(\.selectedGame) private var game
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTabView.selectionKey) private var settingsTab = SettingsTabView.Tab.general

    var body: some Commands {
        CommandMenu("Tools") {
            Button("Tidy Up…") {
                Task { await tools.analyzeTidy(romsRoots: roots, from: .library) }
            }
            .disabled(roots.isEmpty || tools.isBusy)

            Button("Compress Games…") {
                Task { await tools.analyzeCompression(romsRoots: roots, from: .library) }
            }
            .disabled(roots.isEmpty || tools.isBusy)

            Divider()

            gameItems

            Divider()

            let unzipped = tools.unzippedGamesBytes
            Button(unzipped > 0
                   ? String(localized: "Remove Unzipped Copies (\(ByteCountFormatter.string(fromByteCount: unzipped, countStyle: .file)))")
                   : String(localized: "Remove Unzipped Copies")) {
                tools.emptyUnzippedGames()
            }
            .disabled(unzipped == 0)
            .help("Zipped games are unzipped to be played. The copies can go: a game unzips again when it next starts.")

            Button("Back Up Saves") {
                Task { await tools.backUp(emulationRoot: emulationFolderStore.folder.root) }
            }
            .disabled(tools.isBusy)
            .help("Zips your saves, save states, collections and gamelists into your backup folder.")

            Button("Check BIOS Files…") {
                settingsTab = .bios
                openSettings()
            }
        }
    }

    @ViewBuilder
    private var gameItems: some View {
        let title = game?.title ?? ""
        let compression = game.flatMap { tools.compression(for: $0) }
        let back = game.flatMap { tools.conversionBack(for: $0) }
        switch compression {
        case .discs(let discs)?:
            Button(String(localized: "Compress “\(title)” to CHD")) { run(.discs(discs), title) }
                .disabled(tools.isBusy || tools.chdman == nil)
        case .cartridge(let rom)?:
            Button(String(localized: "Compress “\(title)” to ZIP")) { run(.cartridge(rom), title) }
                .disabled(tools.isBusy)
        default:
            Button("Compress Selected Game") {}
                .disabled(true)
        }
        if let back {
            Button(String(localized: "Convert “\(title)” Back from CHD")) { run(back, title) }
                .disabled(tools.isBusy || tools.chdman == nil)
        }
    }

    private var roots: [URL] { romsRootsStore.rootURLs }

    private func run(_ conversion: ToolsCoordinator.GameConversion, _ title: String) {
        Task { await tools.run(conversion, title: title, romsRoots: roots, scanCoordinator: scanCoordinator) }
    }
}

/// View › Enter Cabinet Mode.
struct CabinetCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Enter Cabinet Mode") {
                openWindow(id: CabinetView.windowID)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }
}

/// Help › Attic Help (⌘?) opens the help window instead of the system's
/// "Help isn't available" placeholder.
struct HelpCommands: Commands {
    let navigator: HelpNavigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Attic Help") {
                openWindow(id: HelpView.windowID)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

extension HelpNavigator {
    /// Shows `page` in the help window, opening it if needed.
    func open(_ page: HelpPage, with openWindow: OpenWindowAction) {
        selection = page
        openWindow(id: HelpView.windowID)
    }
}
