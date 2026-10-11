import SwiftUI
import SwiftData
import RomsBoxPersistence

@main
struct RomsBoxApp: App {
    let modelContainer: ModelContainer
    @State private var scanCoordinator: ScanCoordinator
    @State private var launchCoordinator = LaunchCoordinator()
    @State private var romsRootsStore: RomsRootsStore
    @State private var emulationFolderStore: EmulationFolderStore
    @State private var retroArchSettingsStore: RetroArchSettingsStore
    @State private var screenScraperCredentialsStore = ScreenScraperCredentialsStore()
    @State private var theGamesDBCredentialsStore = TheGamesDBCredentialsStore()
    @State private var scrapeCoordinator = ScrapeCoordinator()
    @State private var gamepadInputMonitor = GamepadInputMonitor()
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
            ContentView()
                .environment(scanCoordinator)
                .environment(launchCoordinator)
                .environment(romsRootsStore)
                .environment(retroArchSettingsStore)
                .environment(screenScraperCredentialsStore)
                .environment(theGamesDBCredentialsStore)
                .environment(scrapeCoordinator)
                .environment(gamepadInputMonitor)
                .environment(emulatorSetupCoordinator)
                .environment(emulationFolderStore)
                .frame(minWidth: 800, minHeight: 500)
                .task { await scanCoordinator.refreshGameCounts() }
                // Re-runs when the first ROMs folder is chosen, since the
                // Emulation folder's default location derives from it.
                .task(id: romsRootsStore.rootURLs) {
                    emulationFolderStore.prepare(romsRoots: romsRootsStore.rootURLs)
                    retroArchSettingsStore.refresh()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            SidebarCommands()
            InspectorCommands()
            GameCommands(launchCoordinator: launchCoordinator, retroArchStore: retroArchSettingsStore)
        }

        Settings {
            SettingsTabView()
                .environment(scanCoordinator)
                .environment(launchCoordinator)
                .environment(romsRootsStore)
                .environment(retroArchSettingsStore)
                .environment(screenScraperCredentialsStore)
                .environment(theGamesDBCredentialsStore)
                .environment(scrapeCoordinator)
                .environment(emulatorSetupCoordinator)
                .environment(emulationFolderStore)
                .modelContainer(modelContainer)
        }
    }
}
