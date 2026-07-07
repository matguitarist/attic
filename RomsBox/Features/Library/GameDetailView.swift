import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxEmulation

struct GameDetailView: View {
    let game: Game?

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Query(sort: \EmulatorProfile.name) private var customEmulatorProfiles: [EmulatorProfile]

    var body: some View {
        if let game {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GameCoverArtView(url: game.coverArtURL, title: game.title)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .frame(maxWidth: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(game.title)
                        .font(.title2.bold())

                    HStack {
                        Button {
                            game.favorite.toggle()
                        } label: {
                            Label(game.favorite ? "Favorited" : "Favorite", systemImage: game.favorite ? "star.fill" : "star")
                        }

                        playButton(for: game)
                        launchWithMenu(for: game)
                    }

                    if case .failed(let message) = launchCoordinator.state {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }

                    if let description = game.gameDescription, !description.isEmpty {
                        Text(description)
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
        .buttonStyle(.borderedProminent)
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
            Image(systemName: "chevron.down.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Launch with a specific core or emulator for just this game")
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
