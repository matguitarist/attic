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
    @Environment(HelpNavigator.self) private var helpNavigator
    @Environment(\.openWindow) private var openWindow

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

            // One section per kind of machine (Consoles, Handhelds, Arcade,
            // Computers), only for kinds the library actually has.
            ForEach(systems.groupedByCategory(), id: \.category) { group in
                Section(group.category.title) {
                    ForEach(group.systems) { system in
                        Label(system.displayName, systemImage: group.category.symbolName)
                            .lineLimit(1)
                            .badge(system.gameCount)
                            .tag(LibrarySelection.system(system.systemID))
                            .contextMenu {
                                Button("About This System") {
                                    helpNavigator.open(.system(system.systemID), with: openWindow)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
