import SwiftUI
import RomsBoxPersistence

struct LibrarySidebarView: View {
    let systems: [GameSystem]
    @Binding var selection: LibrarySelection?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Games", systemImage: "square.grid.2x2")
                    .tag(Optional(LibrarySelection.allGames))
                Label("Favorites", systemImage: "star.fill")
                    .tag(Optional(LibrarySelection.favorites))
                Label("Recently Played", systemImage: "clock")
                    .tag(Optional(LibrarySelection.recentlyPlayed))
            }

            if !systems.isEmpty {
                Section("Systems") {
                    ForEach(systems) { system in
                        HStack {
                            Label(system.displayName, systemImage: "square.stack")
                            Spacer()
                            Text("\(system.games.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(LibrarySelection.system(system.systemID)))
                    }
                }
            }
        }
        .navigationTitle("RomsBox")
    }
}
