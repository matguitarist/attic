import SwiftUI
import AtticModels
import AtticPersistence

/// The inspector while a collection is shown and no game is selected: its
/// pictures, what's in it, how it finds its games, and its play history.
struct CollectionOverviewView: View {
    let collection: GameCollection

    @Environment(CollectionCoordinator.self) private var collectionCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    /// Bumped after the pictures change, so they're read again.
    @State private var pictureCheck = 0
    @State private var isDropTarget = false

    private var root: URL { CollectionFolders.root(in: emulationFolderStore.folder.root) }

    var body: some View {
        let games = collection.games
        Form {
            Section {
                VStack(spacing: 12) {
                    let _ = pictureCheck
                    if let artwork = picture(CollectionFile.artworkName) {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(.rect(cornerRadius: 8))
                            .dropDestination(for: URL.self) { urls, _ in
                                guard let image = urls.first(where: Self.isImage) else { return false }
                                setPicture(image, as: CollectionFile.artworkName)
                                return true
                            }
                    }
                    if let logo = picture(CollectionFile.logoName) {
                        Button { chooseLogo() } label: {
                            Image(nsImage: logo)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240, maxHeight: 90)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(collection.name)
                        .help("Click to choose another logo, or drop a picture on it")
                        .contextMenu { logoMenu(hasLogo: true) }
                    } else {
                        Text(collection.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .contextMenu { logoMenu(hasLogo: false) }
                        HStack {
                            if let found = CollectionLogos.logo(forCollectionNamed: collection.name) {
                                Button("Use \(found.lastPathComponent)") { setLogo(found) }
                                    .help(found.path)
                            }
                            Button("Add Logo…") { chooseLogo() }
                        }
                        .controlSize(.small)
                    }
                    Text(summary(games))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                // A picture dropped here becomes the logo; on the artwork,
                // the artwork.
                .dropDestination(for: URL.self) { urls, _ in
                    guard let image = urls.first(where: Self.isImage) else { return false }
                    setPicture(image, as: CollectionFile.logoName)
                    return true
                } isTargeted: { isDropTarget = $0 }
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
            }

            Section {
                Button("Edit Collection…") { collectionCoordinator.edit(collection) }
                Button("Export…") { CollectionFolders.export(collection, root: root) }
                Button("Show in Finder") { CollectionFolders.showInFinder(collection, root: root) }
            }

            let systems = systemCounts(games)
            if systems.count > 1 {
                Section("Systems") {
                    ForEach(systems, id: \.name) { system in
                        LabeledContent(system.name, value: "\(system.count)")
                    }
                }
            }

            Section("Search") {
                if collection.search.isEmpty {
                    Text("None: games are added by hand. Edit the collection to give it a search.")
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Titles containing", value: collection.search.includedTerms.formatted(.list(type: .or)))
                    if !collection.search.excludedTerms.isEmpty {
                        LabeledContent("But not", value: collection.search.excludedTerms.formatted(.list(type: .or)))
                    }
                    if let system = collection.searchSystemID {
                        LabeledContent("On", value: SystemTaxonomy.definition(for: CanonicalSystemID(system))?.displayName ?? system)
                    }
                    LabeledContent("New Games", value: collection.addsMatchingGames ? String(localized: "Added automatically") : String(localized: "Added by hand"))
                }
            }

            let played = games.filter { $0.playCount > 0 }
            if !played.isEmpty {
                Section("Play History") {
                    LabeledContent("Games Played", value: "\(played.count)")
                    let playtime = games.reduce(0) { $0 + $1.totalPlaytimeSeconds }
                    if playtime > 0 {
                        LabeledContent("Total Playtime", value: SystemOverviewView.formattedPlaytime(playtime))
                    }
                    if let last = games.filter({ $0.lastPlayedDate != nil }).max(by: { $0.lastPlayedDate! < $1.lastPlayedDate! }) {
                        LabeledContent("Last Played") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(last.title)
                                if let date = last.lastPlayedDate {
                                    Text(date.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text("Select a game to see its details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        // Pictures picked in the editor show up when it closes.
        .onChange(of: collectionCoordinator.draft == nil) { pictureCheck += 1 }
    }

    @ViewBuilder
    private func logoMenu(hasLogo: Bool) -> some View {
        Button(hasLogo ? String(localized: "Choose Another Logo…") : String(localized: "Add Logo…")) { chooseLogo() }
        if let found = CollectionLogos.logo(forCollectionNamed: collection.name) {
            Button("Use \(found.lastPathComponent)") { setLogo(found) }
        }
        if hasLogo {
            Button("Remove Logo") { setLogo(nil) }
        }
    }

    /// Picks a logo, starting in the logos folder when there's one.
    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = CollectionLogos.folder
        panel.prompt = String(localized: "Choose")
        panel.begin { response in
            if response == .OK, let url = panel.url { setLogo(url) }
        }
    }

    private func setLogo(_ url: URL?) {
        setPicture(url, as: CollectionFile.logoName)
    }

    private func setPicture(_ url: URL?, as name: String) {
        CollectionFolders.setImage(url, as: name, for: collection, root: root)
        pictureCheck += 1
    }

    private static func isImage(_ url: URL) -> Bool {
        CollectionLogos.imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func picture(_ name: String) -> NSImage? {
        CollectionFolders.image(named: name, for: collection, root: root).flatMap(NSImage.init(contentsOf:))
    }

    /// "24 games on 5 systems, 1985–2017".
    private func summary(_ games: [Game]) -> String {
        let systems = Set(games.map(\.systemCanonicalID)).count
        var text = systems > 1
            ? String(localized: "\(games.count) games on \(systems) systems")
            : String(localized: "\(games.count) games")
        let years = games.compactMap(\.releaseDate).map { Calendar(identifier: .gregorian).component(.year, from: $0) }
        if let first = years.min(), let last = years.max() {
            text += first == last ? ", \(first)" : ", \(first)–\(last)"
        }
        return text
    }

    /// Game counts per system, in the sidebar's order.
    private func systemCounts(_ games: [Game]) -> [(name: String, count: Int)] {
        let systems = Dictionary(games.compactMap(\.system).map { ($0.canonicalID, $0) }, uniquingKeysWith: { first, _ in first })
        return systems.values.sorted(by: GameSystem.displayOrder).map { system in
            (system.displayName, games.count { $0.systemCanonicalID == system.canonicalID })
        }
    }
}
