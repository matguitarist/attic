import SwiftUI
import SwiftData
import RomsBoxPersistence

@main
struct RomsBoxApp: App {
    let modelContainer: ModelContainer = {
        do {
            return try RomsBoxModelContainer.makeDefault()
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)
    }
}
