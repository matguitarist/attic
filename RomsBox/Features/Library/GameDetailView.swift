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
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore
    @Query(sort: \EmulatorProfile.name) private var customEmulatorProfiles: [EmulatorProfile]

    var body: some View {
        if let game {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Button {
                            game.favorite.toggle()
                        } label: {
                            Label(game.favorite ? "Favorited" : "Favorite", systemImage: game.favorite ? "star.fill" : "star")
                        }
                        .buttonStyle(.glass)

                        playButton(for: game)
                        launchWithMenu(for: game)
                        scrapeMenu(for: game)
                    }

                    if case .failed(let message) = launchCoordinator.state {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }
                    if case .failed(let message) = scrapeCoordinator.state {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }

                    // Fixed card size regardless of the system — real box art
                    // proportions vary wildly (NES portrait, SNES landscape,
                    // GBA near-square), so GameCoverArtView fits the whole
                    // image inside this frame rather than cropping.
                    GameCoverArtView(url: game.coverArtURL, title: game.title)
                        .frame(width: 220, height: 220 / (3.0 / 4.0))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    TextField("Title", text: titleBinding(for: game))
                        .textFieldStyle(.plain)
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: optionalTextBinding(\.gameDescription, for: game))
                            .font(.callout)
                            .frame(minHeight: 90, maxHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        editableRow("Developer", optionalTextBinding(\.developer, for: game))
                        editableRow("Publisher", optionalTextBinding(\.publisher, for: game))
                        editableRow("Genre", optionalTextBinding(\.genre, for: game))
                        editableRow("Players", optionalTextBinding(\.players, for: game))
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
    private func scrapeMenu(for game: Game) -> some View {
        let isScraping = scrapeCoordinator.state == .scraping

        Menu {
            Button("ScreenScraper") {
                Task { await scrapeCoordinator.scrapeUsingScreenScraper(game: game, credentials: screenScraperCredentialsStore.credentials) }
            }
            .disabled(!screenScraperCredentialsStore.isConfigured)

            Button("TheGamesDB") {
                Task { await scrapeCoordinator.scrapeUsingTheGamesDB(game: game, credentials: theGamesDBCredentialsStore.credentials) }
            }
            .disabled(!theGamesDBCredentialsStore.isConfigured)
        } label: {
            if isScraping {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "photo.badge.magnifyingglass")
            }
        }
        .buttonStyle(.glass)
        .menuStyle(.button)
        .fixedSize()
        .disabled(isScraping || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
        .help("Scrape missing info from ScreenScraper or TheGamesDB")
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

    private func editableRow(_ label: String, _ value: Binding<String>) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            // Placeholder is deliberately generic rather than repeating
            // `label` — an empty field showing e.g. "Developer" as its own
            // placeholder reads exactly like a real (wrong) value at a
            // glance, not like empty/unset.
            TextField("Not set", text: value)
                .textFieldStyle(.plain)
        }
    }

    /// `title` isn't optional, but keeping it in sync with `sortTitle` on
    /// edit matters — that's the field sort actually runs on, and it has
    /// no UI of its own, so a manually retitled game would otherwise sort
    /// under its old name.
    private func titleBinding(for game: Game) -> Binding<String> {
        Binding(
            get: { game.title },
            set: { newValue in
                game.title = newValue
                game.sortTitle = newValue
                game.metadataManuallyEdited = true
                try? game.modelContext?.save()
            }
        )
    }

    /// Empty text commits as `nil` rather than `""`, matching how scraped/
    /// imported data represents "no value" — an editable field cleared out
    /// by the user should look the same as one that was never populated.
    private func optionalTextBinding(_ keyPath: ReferenceWritableKeyPath<Game, String?>, for game: Game) -> Binding<String> {
        Binding(
            get: { game[keyPath: keyPath] ?? "" },
            set: { newValue in
                game[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                game.metadataManuallyEdited = true
                try? game.modelContext?.save()
            }
        )
    }
}
