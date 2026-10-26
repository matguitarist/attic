import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// Games whose info is likely another game's — a description that opens by
/// naming a different one — to scrape again, clear, or keep.
struct GameInfoHealthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore
    @State private var doubtful: [Doubtful]?
    @State private var selection: Set<String> = []
    /// Games the user said are right, by their file's path.
    @AppStorage("gameInfoLooksRight") private var looksRightList = ""
    /// Bumped to check again.
    @State private var checks = 0

    struct Doubtful: Identifiable {
        let id: String
        let game: Game
        let named: String
    }

    private var looksRight: Set<String> {
        Set(looksRightList.split(separator: "\n").map(String.init))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let doubtful {
                let shown = doubtful.filter { !looksRight.contains($0.id) }
                if shown.isEmpty {
                    ContentUnavailableView("Nothing Looks Wrong", systemImage: "checkmark.seal",
                                           description: Text("No description opens by naming another game."))
                } else {
                    header(shown)
                    Divider()
                    List(shown, selection: $selection) { item in
                        row(item)
                    }
                    .listStyle(.inset)
                }
            } else {
                ProgressView("Reading your games’ info…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: checks) { await check() }
        // A scrape done meanwhile changes what's doubtful.
        .onChange(of: scrapeCoordinator.isBatchRunning) { _, running in
            if !running { checks += 1 }
        }
    }

    private func check() async {
        let games = (try? modelContext.fetch(FetchDescriptor<Game>())) ?? []
        let entries = games.map {
            MetadataCheck.Game(id: $0.romAbsolutePath, title: $0.title,
                               romName: ($0.romRelativePath as NSString).deletingPathExtension, description: $0.gameDescription)
        }
        let doubts = await Task.detached(priority: .userInitiated) { MetadataCheck.doubts(entries) }.value
        doubtful = games.compactMap { game in
            guard case .describesAnotherGame(let named)? = doubts[game.romAbsolutePath] else { return nil }
            return Doubtful(id: game.romAbsolutePath, game: game, named: named)
        }
        .sorted { ($0.game.system?.displayName ?? "", $0.game.title) < ($1.game.system?.displayName ?? "", $1.game.title) }
    }

    private func header(_ shown: [Doubtful]) -> some View {
        let chosen = shown.filter { selection.contains($0.id) }
        let games = (chosen.isEmpty ? shown : chosen).map(\.game)
        return HStack {
            Text("\(shown.count) games whose description is likely another game’s")
                .font(.headline)
            Spacer()
            Menu(chosen.isEmpty ? String(localized: "Replace Info of All") : String(localized: "Replace Info of \(chosen.count)")) {
                Button("From ScreenScraper") {
                    scrapeCoordinator.scrape(games: games, from: .screenScraper(screenScraperCredentialsStore.credentials), force: true)
                }
                .disabled(!screenScraperCredentialsStore.isConfigured)
                Button("From TheGamesDB") {
                    scrapeCoordinator.scrape(games: games, from: .theGamesDB(theGamesDBCredentialsStore.credentials), force: true)
                }
                .disabled(!theGamesDBCredentialsStore.isConfigured)
                Button("From LaunchBox") {
                    scrapeCoordinator.scrape(games: games, from: .launchBox, force: true)
                }
            }
            .fixedSize()
            .disabled(scrapeCoordinator.isBatchRunning)
            .help("Scrapes these games again, replacing the info they have")
        }
        .padding(12)
    }

    private func row(_ item: Doubtful) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.game.title).fontWeight(.medium)
                    Text(item.game.system?.displayName ?? item.game.systemCanonicalID)
                        .foregroundStyle(.secondary)
                }
                Text("Its description is about “\(item.named)”")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text(item.game.gameDescription ?? "")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Looks Right") {
                looksRightList = (looksRight.union([item.id])).sorted().joined(separator: "\n")
            }
            .buttonStyle(.link)
            .help("It's this game under another name: don't list it again")
            Button("Clear Description") {
                item.game.gameDescription = nil
                item.game.metadataManuallyEdited = true
                try? modelContext.save()
                checks += 1
            }
            .buttonStyle(.link)
        }
        .padding(.vertical, 3)
    }
}
