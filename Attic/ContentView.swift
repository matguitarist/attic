import SwiftUI
import SwiftData
import AtticPersistence

/// Dispatches between the first-run empty state and the real library
/// browser based on whether anything has been scanned yet.
struct ContentView: View {
    @Query private var systems: [GameSystem]
    @Environment(GamepadInputMonitor.self) private var gamepad

    var body: some View {
        // Cabinet Mode hides this window; the library isn't kept loaded
        // behind it, querying and redrawing for nobody.
        if gamepad.isCabinetActive {
            Color.clear
        } else if systems.isEmpty {
            ChooseROMsRootView()
        } else {
            LibraryBrowserView()
        }
    }
}

#Preview {
    let container = try! AtticModelContainer.makeInMemory()
    let defaults = UserDefaults(suiteName: "preview")!
    let emulationFolderStore = EmulationFolderStore(userDefaults: defaults, romsRoots: [])
    let controllerSettingsStore = ControllerSettingsStore(userDefaults: defaults, emulationFolderStore: emulationFolderStore)
    ContentView()
        .modelContainer(container)
        .environment(ScanCoordinator(libraryStore: LibraryStore(modelContainer: container)))
        .environment(LaunchCoordinator(controllerSettingsStore: controllerSettingsStore))
        .environment(controllerSettingsStore)
        .environment(HelpNavigator())
        .environment(RomsRootsStore(userDefaults: defaults))
        .environment(RetroArchSettingsStore(userDefaults: defaults, emulationFolderStore: emulationFolderStore))
}
