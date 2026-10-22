import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// Settings › Collections: every collection, shown or hidden, and the
/// ready-made series and kinds of games one switch away from being one.
struct CollectionsSettingsView: View {
    @Query(sort: \GameCollection.name) private var collections: [GameCollection]
    @Environment(\.modelContext) private var modelContext
    /// How many of the library's games each template finds, by name.
    @State private var matchCounts: [String: Int]?

    var body: some View {
        let unused = SeriesTemplate.all.filter { template in
            !collections.contains { SeriesTemplate.named($0.name)?.id == template.id }
        }
        Form {
            Section {
                if collections.isEmpty {
                    Text("No collections yet: switch on a series below, or make one with File › New Collection.")
                        .foregroundStyle(.secondary)
                }
                ForEach(collections) { collection in
                    Toggle(isOn: Binding(
                        get: { !collection.isHidden },
                        set: { shown in
                            collection.isHidden = !shown
                            try? modelContext.save()
                        }
                    )) {
                        Text(collection.name)
                        Text("^[\(collection.games.count) game](inflect: true)")
                    }
                }
            } header: {
                Text("Your Collections")
            } footer: {
                Text("A hidden collection keeps its games and settings, and is only left out of the sidebar and Cabinet Mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            templateSection(unused.filter { !$0.isGenre }, title: "Series")
            templateSection(unused.filter(\.isGenre), title: "Kinds of Games")
        }
        .formStyle(.grouped)
        .task { await countMatches() }
    }

    @ViewBuilder
    private func templateSection(_ templates: [SeriesTemplate], title: LocalizedStringKey) -> some View {
        let found = templates.filter { (matchCounts?[$0.name] ?? 0) > 0 }
        let none = templates.count - found.count
        Section {
            if matchCounts == nil {
                ProgressView().controlSize(.small)
            }
            ForEach(found) { template in
                Toggle(isOn: Binding(get: { false }, set: { if $0 { add(template) } })) {
                    Text(template.name)
                    Text("^[\(matchCounts?[template.name] ?? 0) game](inflect: true) in your library")
                }
            }
        } header: {
            Text(title)
        } footer: {
            if matchCounts != nil {
                Text(none == 0 ? "Switching one on makes it a collection that adds new matching games after each scan."
                               : "Switching one on makes it a collection that adds new matching games after each scan. \(none) more have no games in your library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Makes `template` a collection of the games it finds, adding new ones
    /// after each scan.
    private func add(_ template: SeriesTemplate) {
        let collection = GameCollection(name: template.name)
        modelContext.insert(collection)
        collection.search = template.search
        collection.addsMatchingGames = true
        let games = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        collection.games = games.filter { collection.searchMatches($0) }
        try? modelContext.save()
        AppLog.post(.info, "Made the \(template.name) collection: \(collection.games.count) games")
    }

    /// Counted away from the main thread: thousands of games against
    /// every template.
    private func countMatches() async {
        let games = ((try? modelContext.fetch(FetchDescriptor<Game>())) ?? []).map(\.searchable)
        let counts = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: SeriesTemplate.all.map { template in
                (template.name, games.count { template.search.matches($0) })
            })
        }.value
        matchCounts = counts
    }
}
