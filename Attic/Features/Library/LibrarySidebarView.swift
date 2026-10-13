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
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(\.importROMs) private var importROMs
    @AppStorage(SystemSortOrder.key) private var sortOrder = SystemSortOrder.manufacturer
    @State private var systemToRemove: GameSystem?
    @AppStorage(Self.hideEmptySystemsKey) private var hidesEmptySystems = false
    /// Also in Settings › General.
    static let hideEmptySystemsKey = "hideEmptySystems"

    var body: some View {
        // `groupedByCategory()` reads the order itself; this redraws on change.
        let _ = sortOrder
        List(selection: $selection) {
            Section("Library") {
                Label("All Games", systemImage: "square.grid.2x2")
                    .tag(LibrarySelection.allGames)
                Label("Favorites", systemImage: "star")
                    .tag(LibrarySelection.favorites)
                Label("Recently Played", systemImage: "clock")
                    .tag(LibrarySelection.recentlyPlayed)
                Label("Recently Added", systemImage: "sparkles")
                    .tag(LibrarySelection.recentlyAdded)
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
                            Button("Edit Collection…") { collectionCoordinator.edit(collection) }
                            Button("Export…") { CollectionFolders.export(collection, root: CollectionFolders.root(in: emulationFolderStore.folder.root)) }
                            Button("Show in Finder") { CollectionFolders.showInFinder(collection, root: CollectionFolders.root(in: emulationFolderStore.folder.root)) }
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
                    Text(group.category.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .padding(.bottom, 4)
                }
            }
        }
        .listStyle(.sidebar)
        // Smaller rows and icons than the system's default, so long lists
        // of systems fit; all rows alike, so the sections stay even.
        .environment(\.sidebarRowSize, .small)
        .removeSystemConfirmation($systemToRemove)
        // In the sidebar's own toolbar, next to its show/hide button.
        .toolbar {
            ToolbarItem {
                sortMenu
            }
        }
    }

    /// One order for every kind of system, plus hiding empty ones.
    private var sortMenu: some View {
        Menu {
            Picker("Sort Systems By", selection: $sortOrder) {
                ForEach(SystemSortOrder.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Hide Empty Systems", isOn: $hidesEmptySystems)
        } label: {
            Label("Sort Systems", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort systems, or hide empty ones")
    }

    private func systemRow(_ system: GameSystem, category: SystemCategory) -> some View {
        Label(system.displayName, systemImage: category.symbolName)
            .lineLimit(1)
            .badge(system.gameCount)
            .tag(LibrarySelection.system(system.systemID))
            // Games dropped on a system go to its folder, whatever their type.
            .dropDestination(for: URL.self) { urls, _ in
                importROMs(urls, system.systemID)
                return true
            }
            .contextMenu {
                Button("System Settings…") { systemSettingsEditor.system = system }
                Divider()
                ScrapeSelectionMenu(title: "Scrape This System", selection: .system(system.systemID))
                if ToolsCoordinator.canVerify(system.systemID) {
                    Button("Verify Games…") {
                        Task { await tools.verify(datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator, from: .library, system: system.systemID) }
                    }
                    .disabled(tools.isBusy || system.gameCount == 0)
                }
                Divider()
                Button("About This System") {
                    helpNavigator.open(.system(system.systemID), with: openWindow)
                }
                Divider()
                Button("Remove from Library…", role: .destructive) { systemToRemove = system }
            }
    }

}

/// Files games dropped on a sidebar system into its folder (see
/// `ROMImportCoordinator`).
struct ImportROMsAction {
    let run: ([URL], CanonicalSystemID) -> Void

    func callAsFunction(_ urls: [URL], _ system: CanonicalSystemID) { run(urls, system) }
}

extension EnvironmentValues {
    @Entry var importROMs = ImportROMsAction { _, _ in }
}
