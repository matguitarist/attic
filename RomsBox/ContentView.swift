import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence

/// Placeholder root view with a Phase 2 persistence smoke test. Replaced by
/// the NavigationSplitView library browser in Phase 6.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.title) private var games: [Game]

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("RomsBox")
                .font(.title)

            Button("Insert Dummy Game (Phase 2 persistence check)") {
                insertDummyGame()
            }

            List(games) { game in
                Text(game.title)
            }
            .frame(minHeight: 100)
        }
        .frame(width: 480, height: 360)
        .padding()
    }

    private func insertDummyGame() {
        let system = GameSystem(
            canonicalID: .snes,
            displayName: "Super Nintendo Entertainment System",
            romsRootURL: URL(fileURLWithPath: "/tmp/roms/snes"),
            libraryFormat: .esde
        )
        modelContext.insert(system)

        let game = Game(
            system: system,
            systemCanonicalID: .snes,
            romRelativePath: "dummy-\(UUID().uuidString.prefix(4)).sfc",
            romAbsoluteURL: URL(fileURLWithPath: "/tmp/roms/snes/dummy.sfc"),
            title: "Dummy Game \(Date.now.formatted(date: .omitted, time: .standard))"
        )
        modelContext.insert(game)

        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .modelContainer(try! RomsBoxModelContainer.makeInMemory())
}
