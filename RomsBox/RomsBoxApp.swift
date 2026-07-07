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
                .frame(minWidth: 800, minHeight: 500)
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsTabView()
                .environment(scanCoordinator)
                .environment(launchCoordinator)
                .environment(romsRootsStore)
                .environment(retroArchSettingsStore)
                .modelContainer(modelContainer)
        }
    }
}
