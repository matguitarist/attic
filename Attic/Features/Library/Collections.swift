import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// What the library window's collection sheet is doing: making a new
/// collection (optionally with games already in it) or editing one.
struct CollectionDraft: Identifiable {
    enum Mode {
        case new(games: [Game])
        case edit(GameCollection)
    }

    let id = UUID()
    let mode: Mode
}

/// Opens the library window's collection sheet and delete confirmation.
/// One per library window, shared with the sidebar, grid, inspector and
/// menu bar so they all open the same sheet.
@Observable
@MainActor
final class CollectionCoordinator {
    var draft: CollectionDraft?
    var pendingDeletion: GameCollection?

    func newCollection(with games: [Game] = []) {
        draft = CollectionDraft(mode: .new(games: games))
    }

    func edit(_ collection: GameCollection) {
        draft = CollectionDraft(mode: .edit(collection))
    }
}

extension FocusedValues {
    @Entry var collectionCoordinator: CollectionCoordinator?
}

/// "Add to Collection" submenu: one checkable item per collection, then
/// "New Collection…" to make one with this game already in it.
struct AddToCollectionMenu: View {
    let game: Game

    @Query(sort: \GameCollection.name) private var collections: [GameCollection]
    @Environment(CollectionCoordinator.self) private var coordinator

    var body: some View {
        Menu("Add to Collection") {
            ForEach(collections) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: { collection.contains(game) },
                    set: { isMember in
                        collection.setContains(game, isMember)
                        try? game.modelContext?.save()
                    }
                ))
            }
            if !collections.isEmpty {
                Divider()
            }
            Button("New Collection…") {
                coordinator.newCollection(with: [game])
            }
        }
    }
}

/// Makes a collection, or renames one and adds to it. Games are found by
/// title: any of several terms ("Super Mario, Mario Bros"), none of some
/// others ("Tennis, Kart"), optionally on one system — then each match can
/// be unticked before they're added.
struct CollectionEditorView: View {
    let draft: CollectionDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.sortTitle) private var games: [Game]
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @State private var name: String
    @State private var search = CollectionSearch()
    /// The search follows the name until it's edited itself.
    @State private var searchFollowsName: Bool
    @State private var system: CanonicalSystemID?
    @State private var unticked: Set<PersistentIdentifier> = []
    var onCreate: (GameCollection) -> Void = { _ in }

    init(draft: CollectionDraft, onCreate: @escaping (GameCollection) -> Void = { _ in }) {
        self.draft = draft
        self.onCreate = onCreate
        if case .edit(let collection) = draft.mode {
            _name = State(initialValue: collection.name)
            _searchFollowsName = State(initialValue: false)
        } else {
            _name = State(initialValue: "")
            _searchFollowsName = State(initialValue: true)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var editedCollection: GameCollection? {
        if case .edit(let collection) = draft.mode { collection } else { nil }
    }

    /// Games given up front ("Add to New Collection…"), always added.
    private var givenGames: [Game] {
        if case .new(let games) = draft.mode { games } else { [] }
    }

    /// Games the search finds that aren't in the collection yet.
    private var matches: [Game] {
        guard !search.isEmpty else { return [] }
        let skipped = Set((editedCollection?.games ?? []).map(\.persistentModelID))
            .union(givenGames.map(\.persistentModelID))
        return games.filter { game in
            !skipped.contains(game.persistentModelID)
                && (system == nil || game.systemCanonicalID == system?.rawValue)
                && search.matches(game.title)
        }
    }

    private var chosen: [Game] { matches.filter { !unticked.contains($0.persistentModelID) } }

    var body: some View {
        let matches = self.matches
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("e.g. Mario"))
                    .onChange(of: name) {
                        if searchFollowsName { search.including = trimmedName }
                    }
            } header: {
                Text(editedCollection == nil ? String(localized: "New Collection") : String(localized: "Edit Collection"))
                    .font(.headline)
            }

            Section {
                TextField("Titles containing", text: Binding(
                    get: { search.including },
                    set: { search.including = $0; searchFollowsName = false }
                ), prompt: Text("Super Mario, Mario Bros"))
                TextField("But not", text: $search.excluding, prompt: Text("Tennis, Golf, Kart"))
                Picker("On", selection: $system) {
                    Text("All Systems").tag(CanonicalSystemID?.none)
                    Divider()
                    ForEach(systems.filter { $0.gameCount > 0 }) { system in
                        Text(system.displayName).tag(Optional(system.systemID))
                    }
                }
            } header: {
                Text(editedCollection == nil ? String(localized: "Add Games") : String(localized: "Add More Games"))
            } footer: {
                Text("Separate several words with commas: a game is added when its title contains any of the first ones and none of the others.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !matches.isEmpty {
                Section {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(matches) { game in
                                Toggle(isOn: Binding(
                                    get: { !unticked.contains(game.persistentModelID) },
                                    set: { if $0 { unticked.remove(game.persistentModelID) } else { unticked.insert(game.persistentModelID) } }
                                )) {
                                    HStack {
                                        Text(game.title).lineLimit(1)
                                        Spacer()
                                        Text(game.system?.displayName ?? game.systemCanonicalID)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 240)
                } header: {
                    HStack {
                        Text("\(chosen.count) of \(matches.count) games")
                        Spacer()
                        Button("All") { unticked = [] }
                        Button("None") { unticked = Set(matches.map(\.persistentModelID)) }
                    }
                    .buttonStyle(.link)
                }
            } else if !search.isEmpty {
                Text("No other games match.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onChange(of: search) { unticked = [] }
        .onChange(of: system) { unticked = [] }
    }

    private var confirmTitle: String {
        let count = chosen.count
        if editedCollection != nil {
            return count == 0 ? String(localized: "Save") : String(localized: "Save and Add \(count)")
        }
        return String(localized: "Create")
    }

    private func save() {
        let added = chosen
        if let collection = editedCollection {
            collection.name = trimmedName
            for game in added { collection.setContains(game, true) }
        } else {
            let collection = GameCollection(name: trimmedName)
            modelContext.insert(collection)
            collection.games = givenGames + added
            try? modelContext.save()
            onCreate(collection)
        }
        try? modelContext.save()
        dismiss()
    }
}
