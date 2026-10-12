import SwiftUI
import SwiftData
import AtticPersistence

/// Context-menu items for several selected games at once (⌘A, ⌘-click,
/// ⇧-click in the grid): favorite, collect, scrape or reveal them all.
struct MultipleGamesMenuItems: View {
    let games: [Game]
    /// The collection being viewed, if any, for "Remove from…".
    var shownCollection: GameCollection?

    @Query(sort: \GameCollection.name) private var collections: [GameCollection]
    @Environment(CollectionCoordinator.self) private var collectionCoordinator

    var body: some View {
        Text("\(games.count) Games Selected")

        Divider()

        let allFavorite = games.allSatisfy(\.favorite)
        Button(allFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) {
            for game in games { game.favorite = !allFavorite }
            try? games.first?.modelContext?.save()
        }

        Menu("Add to Collection") {
            ForEach(collections) { collection in
                Button(collection.name) {
                    for game in games { collection.setContains(game, true) }
                    try? collection.modelContext?.save()
                }
            }
            if !collections.isEmpty {
                Divider()
            }
            Button("New Collection…") {
                collectionCoordinator.newCollection(with: games)
            }
        }

        if let shownCollection {
            Button("Remove from “\(shownCollection.name)”") {
                for game in games { shownCollection.setContains(game, false) }
                try? shownCollection.modelContext?.save()
            }
        }

        Divider()

        Menu("Scrape Info") {
            MultipleGamesScrapeItems(games: games)
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(games.map(\.romAbsoluteURL))
        }
    }
}

/// Scrape sources for a set of games, mirroring `ScrapeMenuItems`.
struct MultipleGamesScrapeItems: View {
    let games: [Game]

    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

    var body: some View {
        sourceButtons(force: false)
        Divider()
        Menu("Replace Existing Info") {
            sourceButtons(force: true)
        }
    }

    @ViewBuilder
    private func sourceButtons(force: Bool) -> some View {
        Button("ScreenScraper") {
            scrapeCoordinator.scrape(games: games, from: .screenScraper(screenScraperCredentialsStore.credentials), force: force)
        }
        .disabled(!screenScraperCredentialsStore.isConfigured)

        Button("TheGamesDB") {
            scrapeCoordinator.scrape(games: games, from: .theGamesDB(theGamesDBCredentialsStore.credentials), force: force)
        }
        .disabled(!theGamesDBCredentialsStore.isConfigured)
    }
}

/// The inspector while several games are selected: their covers fanned
/// out, how many, and the same actions as the context menu.
struct MultipleGamesSummaryView: View {
    let games: [Game]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(games.prefix(3).enumerated().reversed()), id: \.offset) { index, game in
                    GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(radius: 4)
                        .rotationEffect(.degrees(Double(index) * 6 - 6))
                        .offset(x: CGFloat(index) * 18 - 18)
                }
            }
            .frame(height: 190)

            Text("\(games.count) Games Selected")
                .font(.title2.bold())

            Menu {
                MultipleGamesMenuItems(games: games)
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .fixedSize()

            Text("⌘-click to add or remove a game, ⇧-click to select a range, ⌘A to select everything shown.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
