import SwiftUI
import SwiftData
import AtticPersistence

/// LaunchBox's games database: what's downloaded, and getting it again.
struct LaunchBoxSettingsView: View {
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Query(filter: #Predicate<GameSystem> { $0.gameCount > 0 }) private var systems: [GameSystem]

    var body: some View {
        let store = scrapeCoordinator.launchBox
        Form {
            Section("LaunchBox Games Database") {
                Text("LaunchBox's community database of games: descriptions, facts, box art, 3D boxes, logos, screenshots, fan art, cartridges and discs. It needs no account, and finds games by their file's name, so No-Intro names and MAME sets match well.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Attic downloads it (about 110 MB) the first time you scrape from LaunchBox, keeps only your systems' games, and gets it again each month.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("gamesdb.launchbox-app.com", destination: URL(string: "https://gamesdb.launchbox-app.com/")!)
            }

            Section {
                HStack(spacing: 10) {
                    switch store.state {
                    case .downloading:
                        ProgressView().controlSize(.small)
                        Text("Downloading LaunchBox's database…")
                    case .indexing:
                        ProgressView().controlSize(.small)
                        Text("Keeping your systems’ games…")
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).foregroundStyle(.secondary)
                    case .idle:
                        if let built = store.builtAt {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(store.gameCount) games, \(ByteCountFormatter.string(fromByteCount: store.fileSize, countStyle: .file)), updated \(built.formatted(.relative(presentation: .named)))")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                            Text("Not downloaded yet.").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                HStack {
                    Button(store.isDownloaded ? String(localized: "Update Now") : String(localized: "Download Now")) {
                        Task { await store.update(for: systems.map(\.systemID)) }
                    }
                    Button("Remove", role: .destructive) { store.remove() }
                        .disabled(!store.isDownloaded)
                }
                .disabled(store.isBusy)
            }
        }
        .formStyle(.grouped)
    }
}
