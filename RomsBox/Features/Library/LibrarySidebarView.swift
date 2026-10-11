import SwiftUI
import RomsBoxPersistence

/// A plain native `List(selection:)` sidebar, so macOS draws the selection,
/// badges, section headers and vibrancy itself and they track whatever the
/// current OS release's sidebar looks like.
///
/// An earlier version replaced this with hand-rolled Buttons because
/// selection seemed not to stick. Every row's `.tag` must be exactly a
/// `LibrarySelection` (the selection's wrapped type) for List to match
/// rows to the binding — keep it that way when adding rows.
struct LibrarySidebarView: View {
    let systems: [GameSystem]
    @Binding var selection: LibrarySelection?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Games", systemImage: "square.grid.2x2")
                    .tag(LibrarySelection.allGames)
                Label("Favorites", systemImage: "star")
                    .tag(LibrarySelection.favorites)
                Label("Recently Played", systemImage: "clock")
                    .tag(LibrarySelection.recentlyPlayed)
            }

            if !systems.isEmpty {
                Section("Systems") {
                    ForEach(systems) { system in
                        Label(system.displayName, systemImage: "gamecontroller")
                            .lineLimit(1)
                            .badge(system.gameCount)
                            .tag(LibrarySelection.system(system.systemID))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
