import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxEmulation

struct GameDetailView: View {
    let game: Game?

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Query(sort: \EmulatorProfile.name) private var customEmulatorProfiles: [EmulatorProfile]

    var body: some View {
        if let game {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Fixed card size regardless of the system — real box art
                    // proportions vary wildly (NES portrait, SNES landscape,
                    // GBA near-square), so GameCoverArtView fits the whole
                    // image inside this frame rather than cropping.
                    GameCoverArtView(url: game.coverArtURL, title: game.title)
                        .frame(width: 220, height: 220 / (3.0 / 4.0))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(game.title)
                        .font(.title2.bold())

                    HStack(spacing: 10) {
                        Button {
                            game.favorite.toggle()
                        } label: {
                            Label(game.favorite ? "Favorited" : "Favorite", systemImage: game.favorite ? "star.fill" : "star")
                        }
                        .buttonStyle(.glass)

                        playButton(for: game)
                        launchWithMenu(for: game)
                        scrapeButton(for: game)
                    }

                    if case .failed(let message) = launchCoordinator.state {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }
                    if case .failed(let message) = scrapeCoordinator.state {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }

                    if let description = game.gameDescription, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(description)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        detailRow("Developer", game.developer)
                        detailRow("Publisher", game.publisher)
                        detailRow("Genre", game.genre)
                        detailRow("Players", game.players)
                        if let releaseDate = game.releaseDate {
                            detailRow("Released", releaseDate.formatted(date: .abbreviated, time: .omitted))
                        }
                        if game.playCount > 0 {
                            detailRow("Play Count", "\(game.playCount)")
                        }
                        if game.totalPlaytimeSeconds > 0 {
                            detailRow("Total Playtime", formattedPlaytime(game.totalPlaytimeSeconds))
                        }
                        if let lastPlayed = game.lastPlayedDate {
                            detailRow("Last Played", lastPlayed.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .font(.callout)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Game Selected",
                systemImage: "gamecontroller",
                description: Text("Select a game to see its details.")
            )
        }
    }

    @ViewBuilder
    private func playButton(for game: Game) -> some View {
        let target = resolvedTarget(for: game)
        let isRunningThisGame = launchCoordinator.state == .running(gameID: game.persistentModelID)
        let isBusy = launchCoordinator.state == .launching || isRunningThisGame

        Button {
            launchCoordinator.play(game: game, retroArchStore: retroArchStore)
        } label: {
            Label(isRunningThisGame ? "Running…" : "Play", systemImage: isRunningThisGame ? "gamecontroller.fill" : "play.fill")
        }
        .buttonStyle(.glassProminent)
        .disabled(target == nil || isBusy)
        .help(target == nil ? "Set a default emulator for this system in Settings, or choose one below." : "")
    }

    @ViewBuilder
    private func launchWithMenu(for game: Game) -> some View {
        Menu {
            if game.launchOverride != nil {
                Button("Use System Default") {
                    game.launchOverride = nil
                    try? game.modelContext?.save()
                }
                Divider()
            }

            if let systemID = game.system?.systemID {
                let cores = retroArchStore.cores(for: systemID)
                if !cores.isEmpty {
                    Section("RetroArch Cores") {
                        ForEach(cores) { core in
                            Button(core.displayName) {
                                game.launchOverride = .retroArchCore(coreIdentifier: core.coreIdentifier)
                                try? game.modelContext?.save()
                            }
                        }
                    }
                }

                let matchingProfiles = customEmulatorProfiles.filter { $0.assignedSystemIDs.contains(systemID) }
                if !matchingProfiles.isEmpty {
                    Section("Custom Emulators") {
                        ForEach(matchingProfiles) { profile in
                            Button(profile.name) {
                                game.launchOverride = .emulatorProfile(id: profile.id)
                                try? game.modelContext?.save()
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(.glass)
        .menuStyle(.button)
        .fixedSize()
        .help("Launch with a specific core or emulator for just this game")
    }

    @ViewBuilder
    private func scrapeButton(for game: Game) -> some View {
        let isScraping = scrapeCoordinator.state == .scraping

        Button {
            Task {
                await scrapeCoordinator.scrape(game: game, credentials: screenScraperCredentialsStore.credentials)
            }
        } label: {
            if isScraping {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "photo.badge.magnifyingglass")
            }
        }
        .buttonStyle(.glass)
        .fixedSize()
        .disabled(!screenScraperCredentialsStore.isConfigured || isScraping)
        .help(screenScraperCredentialsStore.isConfigured ? "Scrape missing info from ScreenScraper" : "Add a ScreenScraper devID/devPassword in Settings first")
    }

    private func resolvedTarget(for game: Game) -> LaunchTargetReference? {
        LaunchTargetResolution.resolve(gameOverride: game.launchOverride, systemDefault: game.system?.defaultLaunchTarget)
    }

    private func formattedPlaytime(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value)
            }
        }
    }
}
