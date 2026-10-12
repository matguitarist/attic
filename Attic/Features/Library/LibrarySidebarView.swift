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
    /// Bumped when a sort order changes (stored in UserDefaults, read by
    /// `groupedByCategory()`), so the list redraws.
    @State private var sortOrdersChanged = 0

    var body: some View {
        let _ = sortOrdersChanged
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
            // Computers), only for kinds the library actually has, each
            // sorted as chosen from its header.
            ForEach(systems.groupedByCategory(), id: \.category) { group in
                Section {
                    ForEach(group.systems) { system in
                        systemRow(system, category: group.category)
                    }
                } header: {
                    HStack {
                        Text(group.category.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        sortMenu(for: group.category)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Smaller rows and icons than the system's default, so long lists
        // of systems fit; all rows alike, so the sections stay even.
        .environment(\.sidebarRowSize, .small)
    }

    private func sortMenu(for category: SystemCategory) -> some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { category.sortOrder },
                set: { order in
                    UserDefaults.standard.set(order.rawValue, forKey: category.sortOrderKey)
                    sortOrdersChanged += 1
                }
            )) {
                ForEach(SystemSortOrder.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort By", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort \(category.title)")
    }

    private func systemRow(_ system: GameSystem, category: SystemCategory) -> some View {
        Label(system.displayName, systemImage: category.symbolName)
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
