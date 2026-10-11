import SwiftUI
import SwiftData
import RomsBoxPersistence

@main
struct RomsBoxApp: App {
    let modelContainer: ModelContainer
    @State private var scanCoordinator: ScanCoordinator
    @State private var launchCoordinator = LaunchCoordinator()
    @State private var romsRootsStore = RomsRootsStore()
    @State private var retroArchSettingsStore = RetroArchSettingsStore()
    @State private var screenScraperCredentialsStore = ScreenScraperCredentialsStore()
    @State private var theGamesDBCredentialsStore = TheGamesDBCredentialsStore()
    @State private var scrapeCoordinator = ScrapeCoordinator()
    @State private var gamepadInputMonitor = GamepadInputMonitor()

    init() {
        let container: ModelContainer
        do {
            container = try RomsBoxModelContainer.makeDefault()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        modelContainer = container
        _scanCoordinator = State(initialValue: ScanCoordinator(libraryStore: LibraryStore(modelContainer: container)))
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
                .frame(minWidth: 800, minHeight: 500)
                .task { await scanCoordinator.refreshGameCounts() }
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
                .modelContainer(modelContainer)
        }
    }
}
