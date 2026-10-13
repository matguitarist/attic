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

/// Makes or edits a collection. Games are found by title: any of several
/// terms ("Super Mario, Mario Bros"), none of some others ("Tennis,
/// Kart"), optionally on one system. The collection keeps its search, so
/// editing it later runs it again (after adding a system, say) or changes
/// it, and it can add new matches by itself after each library scan.
/// Every game listed can be unticked: a member to take it out, a match to
/// leave it out — either way the search won't add it back.
struct CollectionEditorView: View {
    let draft: CollectionDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.sortTitle) private var games: [Game]
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @State private var name: String
    @State private var search: CollectionSearch
    /// The search follows the name until it's edited itself.
    @State private var searchFollowsName: Bool
    @State private var system: CanonicalSystemID?
    @State private var addsMatchingGames: Bool
    /// Listed games left unticked: members to take out, matches to skip.
    @State private var unticked: Set<PersistentIdentifier> = []
    /// How many of the library's games each series template finds.
    @State private var templateCounts: [String: Int] = [:]
    /// Pictures picked here, put in place on save: nil leaves the current
    /// one, `.some(nil)` removes it.
    @State private var pendingPictures: [String: URL?] = [:]
    /// The pending logo came from the logos folder, for a template.
    @State private var logoIsFromFolder = false
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    var onCreate: (GameCollection) -> Void = { _ in }

    init(draft: CollectionDraft, onCreate: @escaping (GameCollection) -> Void = { _ in }) {
        self.draft = draft
        self.onCreate = onCreate
        if case .edit(let collection) = draft.mode {
            _name = State(initialValue: collection.name)
            _search = State(initialValue: collection.search)
            _searchFollowsName = State(initialValue: false)
            _system = State(initialValue: collection.searchSystemID.map { CanonicalSystemID($0) })
            _addsMatchingGames = State(initialValue: collection.addsMatchingGames)
        } else {
            _name = State(initialValue: "")
            _search = State(initialValue: CollectionSearch())
            _searchFollowsName = State(initialValue: true)
            _addsMatchingGames = State(initialValue: false)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var editedCollection: GameCollection? {
        if case .edit(let collection) = draft.mode { collection } else { nil }
    }

    /// The collection's games, or those given up front ("Add to New
    /// Collection…").
    private var members: [Game] {
        switch draft.mode {
        case .edit(let collection): collection.games.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
        case .new(let games): games
        }
    }

    /// Games the search finds that aren't members yet.
    private var matches: [Game] {
        guard !search.isEmpty else { return [] }
        let memberIDs = Set(members.map(\.persistentModelID))
        return games.filter { game in
            !memberIDs.contains(game.persistentModelID)
                && (system == nil || game.systemCanonicalID == system?.rawValue)
                && search.matches(game.title)
        }
    }

    private func isTicked(_ game: Game) -> Bool { !unticked.contains(game.persistentModelID) }

    var body: some View {
        let members = self.members
        let matches = self.matches
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("e.g. Mario"))
                    .onChange(of: name) {
                        if searchFollowsName { search.including = trimmedName }
                    }
                if editedCollection == nil {
                    Menu("Start from a Series") {
                        ForEach(SeriesTemplate.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { template in
                            let count = templateCounts[template.name] ?? 0
                            Button(count > 0 ? "\(template.name) (\(count))" : template.name) { apply(template) }
                        }
                    }
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
                Toggle(isOn: $addsMatchingGames) {
                    Text("Add new matching games automatically")
                    Text("After each library scan, for instance once you've added a system.")
                }
                .disabled(search.isEmpty)
            } header: {
                Text("Search")
            } footer: {
                Text("Separate several words with commas: a game is found when its title contains any of the first ones and none of the others.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pictures") {
                pictureRow(String(localized: "Logo"), name: CollectionFile.logoName, help: String(localized: "Shown instead of the name, in the side panel and Cabinet Mode."))
                pictureRow(String(localized: "Artwork"), name: CollectionFile.artworkName, help: String(localized: "A character or key art, above it in the side panel."))
            }

            if !members.isEmpty || !matches.isEmpty {
                Section {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if !members.isEmpty, !matches.isEmpty {
                                Text(editedCollection == nil ? String(localized: "Chosen") : String(localized: "In the collection"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(members) { row($0) }
                            if !members.isEmpty, !matches.isEmpty {
                                Text("Found by the search")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                            }
                            ForEach(matches) { row($0) }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 260)
                } header: {
                    HStack {
                        Text(String(localized: "\((members + matches).count { isTicked($0) }) of \(members.count + matches.count) games"))
                        Spacer()
                        Button("All") { unticked = [] }
                        Button("None") { unticked = Set((members + matches).map(\.persistentModelID)) }
                    }
                    .buttonStyle(.link)
                }
            } else if !search.isEmpty {
                Text("No games match.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editedCollection == nil ? String(localized: "Create") : String(localized: "Save")) { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        // Games left out before start unticked, so they can be put back.
        .task(id: search) { untickExcluded() }
        .task {
            guard editedCollection == nil else { return }
            let titles = games.map(\.title)
            templateCounts = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: SeriesTemplate.all.map { template in
                    (template.name, titles.count { template.search.matches($0) })
                })
            }.value
        }
        .onChange(of: system) { untickExcluded() }
    }

    private var collectionsRoot: URL { CollectionFolders.root(in: emulationFolderStore.folder.root) }

    private func apply(_ template: SeriesTemplate) {
        name = template.name
        search = template.search
        searchFollowsName = false
        system = nil
        addsMatchingGames = true
        // The series' logo from one's logos folder, unless one was picked
        // by hand.
        if pendingPictures[CollectionFile.logoName] == nil || logoIsFromFolder {
            if let logo = CollectionLogos.logo(forCollectionNamed: template.name) {
                pendingPictures[CollectionFile.logoName] = .some(logo)
                logoIsFromFolder = true
            } else if logoIsFromFolder {
                pendingPictures.removeValue(forKey: CollectionFile.logoName)
                logoIsFromFolder = false
            }
        }
    }

    /// The picture as it'll be once saved: picked here, else the current one.
    private func picture(_ name: String) -> URL? {
        if let pending = pendingPictures[name] { return pending }
        return editedCollection.flatMap { CollectionFolders.image(named: name, for: $0, root: collectionsRoot) }
    }

    private func pictureRow(_ title: String, name: String, help: String) -> some View {
        LabeledContent {
            HStack {
                if let url = picture(name), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 36)
                    Button("Remove") {
                        pendingPictures[name] = .some(nil)
                        logoIsFromFolder = false
                    }
                }
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            pendingPictures[name] = .some(url)
                            if name == CollectionFile.logoName { logoIsFromFolder = false }
                        }
                    }
                }
            }
        } label: {
            Text(title)
            Text(help)
        }
    }

    private func row(_ game: Game) -> some View {
        Toggle(isOn: Binding(
            get: { isTicked(game) },
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

    private func untickExcluded() {
        let excluded = Set(editedCollection?.excludedGameKeys ?? [])
        let memberIDs = Set(unticked.filter { id in members.contains { $0.persistentModelID == id } })
        unticked = memberIDs.union(matches.filter { excluded.contains($0.collectionKey) }.map(\.persistentModelID))
    }

    private func save() {
        let members = self.members
        let matches = self.matches
        let collection: GameCollection
        if let editedCollection {
            collection = editedCollection
        } else {
            collection = GameCollection(name: trimmedName)
            modelContext.insert(collection)
        }
        collection.name = trimmedName
        collection.search = search
        collection.searchSystemID = system?.rawValue
        collection.addsMatchingGames = addsMatchingGames && !search.isEmpty

        var excluded = Set(collection.excludedGameKeys)
        for game in members + matches {
            if isTicked(game) {
                collection.setContains(game, true)
                excluded.remove(game.collectionKey)
            } else {
                collection.setContains(game, false)
                excluded.insert(game.collectionKey)
            }
        }
        collection.excludedGameKeys = excluded.sorted()
        try? modelContext.save()
        var pictures = pendingPictures
        // A new collection with no logo picked takes its logos folder's one.
        if editedCollection == nil, pictures[CollectionFile.logoName] == nil,
           let logo = CollectionLogos.logo(forCollectionNamed: trimmedName) {
            pictures[CollectionFile.logoName] = .some(logo)
        }
        for (name, url) in pictures {
            CollectionFolders.setImage(url, as: name, for: collection, root: collectionsRoot)
        }
        if editedCollection == nil { onCreate(collection) }
        dismiss()
    }
}
