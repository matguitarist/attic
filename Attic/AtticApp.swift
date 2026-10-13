import SwiftUI
import SwiftData
import AtticPersistence

@main
struct AtticApp: App {
    let modelContainer: ModelContainer
    @State private var scanCoordinator: ScanCoordinator
    @State private var launchCoordinator: LaunchCoordinator
    @State private var romsRootsStore: RomsRootsStore
    @State private var emulationFolderStore: EmulationFolderStore
    @State private var retroArchSettingsStore: RetroArchSettingsStore
    @State private var screenScraperCredentialsStore = ScreenScraperCredentialsStore()
    @State private var theGamesDBCredentialsStore = TheGamesDBCredentialsStore()
    @State private var scrapeCoordinator = ScrapeCoordinator()
    @State private var gamepadInputMonitor: GamepadInputMonitor
    @State private var controllerSettingsStore: ControllerSettingsStore
    @State private var helpNavigator = HelpNavigator()
    @State private var emulatorSetupCoordinator: EmulatorSetupCoordinator
    @State private var appUpdater = AppUpdater()
    @State private var toolsCoordinator = ToolsCoordinator()
    @State private var shaderPackStore: ShaderPackStore

    init() {
        // Before any store reads its settings.
        LegacyRomsBoxMigration.migrateSettings()
        // One library window: no window tabs (View › Show Tab Bar would
        // open more).
        NSWindow.allowsAutomaticWindowTabbing = false

        let container: ModelContainer
        do {
            container = try AtticModelContainer.makeDefault()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        modelContainer = container
        _scanCoordinator = State(initialValue: ScanCoordinator(libraryStore: LibraryStore(modelContainer: container)))

        let romsRootsStore = RomsRootsStore()
        let emulationFolderStore = EmulationFolderStore(romsRoots: romsRootsStore.rootURLs)
        // At launch, not from a view: the app can come up with no library
        // window open, and the folder must be ready before anything indexes
        // cores or launches a game.
        emulationFolderStore.prepare(romsRoots: romsRootsStore.rootURLs)
        Self.followRenamedFolders(emulationFolderStore.renamedFolders, in: container)
        LegacyRomsBoxMigration.migrateFiles(emulationFolder: emulationFolderStore.folder, modelContainer: container)
        AppSupportMediaMigration.run(in: container)
        _romsRootsStore = State(initialValue: romsRootsStore)
        _emulationFolderStore = State(initialValue: emulationFolderStore)
        _shaderPackStore = State(initialValue: ShaderPackStore(emulationFolderStore: emulationFolderStore))

        let controllerSettingsStore = ControllerSettingsStore(emulationFolderStore: emulationFolderStore)
        let launchCoordinator = LaunchCoordinator(controllerSettingsStore: controllerSettingsStore)
        _controllerSettingsStore = State(initialValue: controllerSettingsStore)
        _launchCoordinator = State(initialValue: launchCoordinator)
        _gamepadInputMonitor = State(initialValue: GamepadInputMonitor(controllerSettingsStore: controllerSettingsStore))
        let retroArchSettingsStore = RetroArchSettingsStore(emulationFolderStore: emulationFolderStore)
        let emulatorSetupCoordinator = EmulatorSetupCoordinator(emulationFolderStore: emulationFolderStore)
        _retroArchSettingsStore = State(initialValue: retroArchSettingsStore)
        _emulatorSetupCoordinator = State(initialValue: emulatorSetupCoordinator)
        // Not tied to a window: the app can launch with none open.
        Task { @MainActor in
            await emulatorSetupCoordinator.refreshCoreCatalogIfStale(retroArchStore: retroArchSettingsStore)
            await emulatorSetupCoordinator.checkForCoreUpdatesIfDue(retroArchStore: retroArchSettingsStore)
        }
    }

    var body: some Scene {
        WindowGroup {
            withAppEnvironment(ContentView())
                // Room for the sidebar, the grid and the game panel. Any
                // narrower and the columns' minimums can't all fit:
                // AppKit kept resizing them until it gave up (a crash at
                // launch for a window saved at 900 points wide).
                .frame(minWidth: 1040, minHeight: 560)
                .task { await scanCoordinator.refreshGameCounts() }
                // The weekly save backup, a minute in so launch stays quick.
                .task {
                    try? await Task.sleep(for: .seconds(60))
                    await toolsCoordinator.backUpIfDue(emulationRoot: emulationFolderStore.folder.root)
                }
                // Each collection's folder follows every save of the library.
                .task {
                    let root = CollectionFolders.root(in: emulationFolderStore.folder.root)
                    CollectionFolders.loadNewFolders(context: modelContainer.mainContext, root: root)
                    saveCollectionFolders()
                    for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                        saveCollectionFolders()
                    }
                }
                // A collection folder copied into Collections while Attic
                // runs joins the library when Attic comes back to the front.
                .task {
                    for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                        CollectionFolders.loadNewFolders(context: modelContainer.mainContext, root: CollectionFolders.root(in: emulationFolderStore.folder.root))
                    }
                }
                // Re-runs when the first ROMs folder is chosen, since the
                // Emulation folder's default location derives from it.
                .task(id: romsRootsStore.rootURLs) {
                    emulationFolderStore.prepare(romsRoots: romsRootsStore.rootURLs)
                    ROMFolderNotes.createSystemFolders(romsRoots: romsRootsStore.rootURLs)
                    ROMFolderNotes.write(romsRoots: romsRootsStore.rootURLs, biosDirectory: emulationFolderStore.folder.bios)
                    retroArchSettingsStore.refresh()
                    controllerSettingsStore.loadProfiles()
                }
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1400, height: 860)
        .commands {
            UpdateCommands(updater: appUpdater)
            SidebarCommands()
            InspectorCommands()
            CabinetCommands()
            LibraryCommands(scanCoordinator: scanCoordinator, romsRootsStore: romsRootsStore)
            GameCommands(launchCoordinator: launchCoordinator, retroArchStore: retroArchSettingsStore)
            ToolsCommands(tools: toolsCoordinator, scanCoordinator: scanCoordinator, romsRootsStore: romsRootsStore, emulationFolderStore: emulationFolderStore)
            HelpCommands(navigator: helpNavigator)
        }

        // Its own window so the library keeps its state underneath; it
        // only ever opens on request — never at launch or via restoration.
        Window("Cabinet Mode", id: CabinetView.windowID) {
            withAppEnvironment(CabinetView())
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        // Full screen requires a resizable window; a Window scene sized to
        // its content alone isn't one.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .modelContainer(modelContainer)

        Window("Attic Help", id: HelpView.windowID) {
            withAppEnvironment(HelpView())
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 900, height: 640)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .modelContainer(modelContainer)

        Settings {
            withAppEnvironment(SettingsTabView())
                .modelContainer(modelContainer)
        }
    }

    /// Games' media paths into folders renamed at launch (ES-DE's
    /// downloaded_media is now Media).
    private static func followRenamedFolders(_ renamed: [(from: URL, to: URL)], in container: ModelContainer) {
        guard !renamed.isEmpty, let games = try? container.mainContext.fetch(FetchDescriptor<Game>()) else { return }
        func moved(_ path: String?) -> String? {
            guard let path else { return nil }
            for (from, to) in renamed where path.hasPrefix(from.path + "/") {
                return to.path + path.dropFirst(from.path.count)
            }
            return path
        }
        for game in games {
            game.coverArtPath = moved(game.coverArtPath)
            game.titleScreenPath = moved(game.titleScreenPath)
            game.videoPath = moved(game.videoPath)
        }
        try? container.mainContext.save()
    }

    private func saveCollectionFolders() {
        let collections = (try? modelContainer.mainContext.fetch(FetchDescriptor<GameCollection>())) ?? []
        CollectionFolders.save(collections, root: CollectionFolders.root(in: emulationFolderStore.folder.root))
    }

    /// Every scene sees the same shared app state.
    private func withAppEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .environment(scanCoordinator)
            .environment(launchCoordinator)
            .environment(romsRootsStore)
            .environment(retroArchSettingsStore)
            .environment(screenScraperCredentialsStore)
            .environment(theGamesDBCredentialsStore)
            .environment(scrapeCoordinator)
            .environment(gamepadInputMonitor)
            .environment(controllerSettingsStore)
            .environment(helpNavigator)
            .environment(emulatorSetupCoordinator)
            .environment(emulationFolderStore)
            .environment(appUpdater)
            .environment(shaderPackStore)
            .environment(toolsCoordinator)
    }
}
