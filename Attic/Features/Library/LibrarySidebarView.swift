import SwiftUI
import AtticModels
import AtticPersistence

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
    let collections: [GameCollection]
    @Binding var selection: LibrarySelection?
    @Environment(HelpNavigator.self) private var helpNavigator
    @Environment(\.openWindow) private var openWindow
    @Environment(CollectionCoordinator.self) private var collectionCoordinator
    @Environment(SystemSettingsEditor.self) private var systemSettingsEditor

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

            Section {
                ForEach(collections) { collection in
                    Label(collection.name, systemImage: "rectangle.stack")
                        .lineLimit(1)
                        .badge(collection.games.count)
                        .tag(LibrarySelection.collection(collection.collectionID))
                        .contextMenu {
                            ScrapeSelectionMenu(title: "Scrape This Collection", selection: .collection(collection.collectionID))
                            Divider()
                            Button("Rename…") { collectionCoordinator.rename(collection) }
                            Button("Delete Collection…", role: .destructive) { collectionCoordinator.pendingDeletion = collection }
                        }
                }
                if collections.isEmpty {
                    Button {
                        collectionCoordinator.newCollection()
                    } label: {
                        Label("New Collection…", systemImage: "plus")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Button {
                        collectionCoordinator.newCollection()
                    } label: {
                        Label("New Collection…", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("New Collection (⇧⌘N)")
                }
            }

            // One section per kind of machine (Consoles, Handhelds, Arcade,
            // Computers), only for kinds the library actually has, with the
            // systems under a small heading per maker (Nintendo, Sega…).
            ForEach(systems.groupedByCategory(), id: \.category) { group in
                Section {
                    ForEach(group.systems.groupedByMaker(), id: \.maker) { makerGroup in
                        // Untagged, so it can't be selected.
                        Text(makerGroup.maker)
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, -4)
                        ForEach(makerGroup.systems) { system in
                            systemRow(system, category: group.category)
                        }
                    }
                } header: {
                    Text(group.category.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func systemRow(_ system: GameSystem, category: SystemCategory) -> some View {
        // The maker is in the heading above, so not repeated here.
        Label(system.systemID.shortName(displayName: system.displayName), systemImage: category.symbolName)
            .help(system.displayName)
            .lineLimit(1)
            .badge(system.gameCount)
            .tag(LibrarySelection.system(system.systemID))
            .contextMenu {
                Button("System Settings…") { systemSettingsEditor.system = system }
                Divider()
                ScrapeSelectionMenu(title: "Scrape This System", selection: .system(system.systemID))
                Divider()
                Button("About This System") {
                    helpNavigator.open(.system(system.systemID), with: openWindow)
                }
            }
    }

}
