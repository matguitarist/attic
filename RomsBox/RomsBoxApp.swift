import SwiftUI
import SwiftData
import RomsBoxPersistence

@main
struct RomsBoxApp: App {
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

    init() {
        let container: ModelContainer
        do {
            container = try RomsBoxModelContainer.makeDefault()
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
        _romsRootsStore = State(initialValue: romsRootsStore)
        _emulationFolderStore = State(initialValue: emulationFolderStore)

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
                .frame(minWidth: 800, minHeight: 500)
                .task { await scanCoordinator.refreshGameCounts() }
                // Re-runs when the first ROMs folder is chosen, since the
                // Emulation folder's default location derives from it.
                .task(id: romsRootsStore.rootURLs) {
                    emulationFolderStore.prepare(romsRoots: romsRootsStore.rootURLs)
                    retroArchSettingsStore.refresh()
                    controllerSettingsStore.loadProfiles()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            SidebarCommands()
            InspectorCommands()
            BigBoxCommands()
            GameCommands(launchCoordinator: launchCoordinator, retroArchStore: retroArchSettingsStore)
            HelpCommands(navigator: helpNavigator)
        }

        // Its own window so the library keeps its state underneath; it
        // only ever opens on request — never at launch or via restoration.
        Window("Big Box", id: BigBoxView.windowID) {
            withAppEnvironment(BigBoxView())
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

        Window("RomsBox Help", id: HelpView.windowID) {
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
    }
}
