import SwiftUI
import SwiftData
import RomsBoxPersistence

@main
struct RomsBoxApp: App {
    let modelContainer: ModelContainer
    @State private var scanCoordinator: ScanCoordinator
    @State private var romsRootsStore = RomsRootsStore()

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
                .environment(romsRootsStore)
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)
    }
}
