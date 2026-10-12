import SwiftUI
import SwiftData
import AtticPersistence

/// What the library window's collection sheet is doing: making a new
/// collection (optionally with games already in it) or renaming one.
struct CollectionDraft: Identifiable {
    enum Mode {
        case new(games: [Game])
        case rename(GameCollection)
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

    func rename(_ collection: GameCollection) {
        draft = CollectionDraft(mode: .rename(collection))
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

/// Names a new collection, or renames one. A new collection can also pick
/// up every game whose title contains its name: "Zelda" gathers the whole
/// series in one go, across systems.
struct CollectionEditorView: View {
    let draft: CollectionDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    @State private var addsMatchingGames = true
    @State private var matchingCount = 0
    var onCreate: (GameCollection) -> Void = { _ in }

    init(draft: CollectionDraft, onCreate: @escaping (GameCollection) -> Void = { _ in }) {
        self.draft = draft
        self.onCreate = onCreate
        if case .rename(let collection) = draft.mode {
            _name = State(initialValue: collection.name)
        } else {
            _name = State(initialValue: "")
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isNew: Bool {
        if case .new = draft.mode { true } else { false }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("e.g. Zelda"))
                if isNew {
                    Toggle(isOn: $addsMatchingGames) {
                        Text("Add games with “\(trimmedName.isEmpty ? "…" : trimmedName)” in the title")
                        Text(trimmedName.isEmpty ? String(localized: "Type a name to find matching games.") : String(localized: "\(matchingCount) games in your library"))
                    }
                    .disabled(trimmedName.isEmpty)
                }
            } header: {
                Text(isNew ? String(localized: "New Collection") : String(localized: "Rename Collection"))
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle(isNew ? String(localized: "New Collection") : String(localized: "Rename Collection"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? String(localized: "Create") : String(localized: "Rename")) { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .task(id: trimmedName) {
            matchingCount = trimmedName.isEmpty ? 0 : ((try? modelContext.fetchCount(FetchDescriptor(predicate: Self.titleContains(trimmedName)))) ?? 0)
        }
    }

    private static func titleContains(_ text: String) -> Predicate<Game> {
        #Predicate<Game> { $0.title.localizedStandardContains(text) }
    }

    private func save() {
        switch draft.mode {
        case .rename(let collection):
            collection.name = trimmedName
        case .new(let games):
            var members = games
            if addsMatchingGames, let matching = try? modelContext.fetch(FetchDescriptor(predicate: Self.titleContains(trimmedName))) {
                let existing = Set(members.map(\.persistentModelID))
                members += matching.filter { !existing.contains($0.persistentModelID) }
            }
            let collection = GameCollection(name: trimmedName)
            modelContext.insert(collection)
            collection.games = members
            try? modelContext.save()
            onCreate(collection)
        }
        try? modelContext.save()
        dismiss()
    }
}
