import SwiftUI
import SwiftData
import RomsBoxPersistence

/// Dispatches between the first-run empty state and the real library
/// browser based on whether anything has been scanned yet.
struct ContentView: View {
    @Query private var systems: [GameSystem]

    var body: some View {
        if systems.isEmpty {
            ChooseROMsRootView()
        } else {
            LibraryBrowserView()
        }
    }
}

#Preview {
    let container = try! RomsBoxModelContainer.makeInMemory()
    ContentView()
        .modelContainer(container)
        .environment(ScanCoordinator(libraryStore: LibraryStore(modelContainer: container)))
        .environment(LaunchCoordinator())
        .environment(RomsRootsStore(userDefaults: UserDefaults(suiteName: "preview")!))
        .environment(RetroArchSettingsStore(
            userDefaults: UserDefaults(suiteName: "preview")!,
            emulationFolderStore: EmulationFolderStore(userDefaults: UserDefaults(suiteName: "preview")!, romsRoots: [])
        ))
}
