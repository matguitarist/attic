import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence

/// Inspector contents for the selected game: a header (art, editable title,
/// actions) above a native grouped `Form`, so labels, fields and section
/// styling all come from the system.
struct GameDetailView: View {
    let game: Game?

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

    var body: some View {
        if let game {
            Form {
                Section {
                    header(for: game)
                }

                Section("Description") {
                    // TextEditor has no Return-to-submit (Return is a
                    // newline), so this one commits on focus loss only.
                    CommitOnBlurField(
                        value: game.gameDescription ?? "",
                        onCommit: { commitOptionalText($0, to: \.gameDescription, for: game) }
                    ) { text, focus in
                        TextEditor(text: text)
                            .font(.callout)
                            .frame(minHeight: 90, maxHeight: 200)
                            .scrollContentBackground(.hidden)
                            .focused(focus)
                    }
                    .labelsHidden()
                }

                Section("Info") {
                    editableRow("Developer", \.developer, for: game)
                    editableRow("Publisher", \.publisher, for: game)
                    editableRow("Genre", \.genre, for: game)
                    editableRow("Players", \.players, for: game)
                    if let releaseDate = game.releaseDate {
                        LabeledContent("Released", value: releaseDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("System", value: game.system?.displayName ?? game.systemCanonicalID)
                }

                if game.playCount > 0 || game.lastPlayedDate != nil {
                    Section("Play History") {
                        LabeledContent("Play Count", value: "\(game.playCount)")
                        if game.totalPlaytimeSeconds > 0 {
                            LabeledContent("Total Playtime", value: formattedPlaytime(game.totalPlaytimeSeconds))
                        }
                        if let lastPlayed = game.lastPlayedDate {
                            LabeledContent("Last Played", value: lastPlayed.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            // Fresh field state per game — see CommitOnBlurField.
            .id(game.persistentModelID)
        } else {
            ContentUnavailableView(
                "No Game Selected",
                systemImage: "gamecontroller",
                description: Text("Select a game to see its details.")
            )
        }
    }

    @ViewBuilder
    private func header(for game: Game) -> some View {
        VStack(spacing: 12) {
            // Fixed frame regardless of the system — real box art
            // proportions vary wildly (NES portrait, SNES landscape, GBA
            // near-square), so GameCoverArtView fits the whole image inside
            // this frame rather than cropping.
            GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false)
                .frame(width: 220, height: 220 / (3.0 / 4.0))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            CommitOnBlurField(
                value: game.title,
                isValid: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                onCommit: { commitTitle($0, for: game) }
            ) { text, focus in
                // Inside a Form, a TextField renders its title as a leading
                // row label ("Title  3 Ninjas…"); the header wants just the
                // centered name.
                TextField("Title", text: text, axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .focused(focus)
            }

            actions(for: game)

            // A per-game override means the user already picked something
            // for this game specifically; only suggest installs otherwise.
            if game.launchOverride == nil, let system = game.system {
                EmulatorSuggestionView(system: system)
            }

            if case .failed(let message) = launchCoordinator.state {
                Text(message).foregroundStyle(.red).font(.callout)
            }
            if case .failed(let message) = scrapeCoordinator.state {
                Text(message).foregroundStyle(.red).font(.callout)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func actions(for game: Game) -> some View {
        let target = LaunchTargetResolution.resolve(gameOverride: game.launchOverride, systemDefault: game.system?.defaultLaunchTarget)
        let isRunningThisGame = launchCoordinator.state == .running(gameID: game.persistentModelID)
        let isBusy = launchCoordinator.state == .launching || isRunningThisGame
        let isScraping = scrapeCoordinator.state == .scraping

        HStack(spacing: 8) {
            Button {
                launchCoordinator.play(game: game, retroArchStore: retroArchStore)
            } label: {
                Label(isRunningThisGame ? "Running…" : "Play", systemImage: isRunningThisGame ? "gamecontroller.fill" : "play.fill")
                    .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(target == nil || isBusy)
            .help(target == nil ? "Set a default emulator for this system in Settings, or choose one from Launch With." : "Play (⌘↩)")

            Button {
                game.favorite.toggle()
                try? game.modelContext?.save()
            } label: {
                Label(game.favorite ? "Unfavorite" : "Favorite", systemImage: game.favorite ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.large)
            .help(game.favorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")

            Menu {
                Menu("Launch With") {
                    LaunchWithMenuItems(game: game)
                }
                Menu("Scrape Info") {
                    ScrapeMenuItems(game: game)
                }
                .disabled(isScraping || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([game.romAbsoluteURL])
                }
            } label: {
                if isScraping {
                    ProgressView().controlSize(.small)
                } else {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
            }
            .menuIndicator(.hidden)
            .controlSize(.large)
            .fixedSize()
            .help("Launch with a specific emulator, scrape info, or reveal the ROM")
        }
    }

    private func formattedPlaytime(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }

    /// A native Form row: the field's label shows on the leading side, the
    /// editable value on the trailing side. The prompt is deliberately
    /// generic rather than repeating the label — an empty field showing
    /// e.g. "Developer" reads like a real (wrong) value, not like unset.
    private func editableRow(_ label: String, _ keyPath: ReferenceWritableKeyPath<Game, String?>, for game: Game) -> some View {
        CommitOnBlurField(
            value: game[keyPath: keyPath] ?? "",
            onCommit: { commitOptionalText($0, to: keyPath, for: game) }
        ) { text, focus in
            TextField(label, text: text, prompt: Text("Not set"))
                .focused(focus)
        }
    }

    /// `title` isn't optional, but keeping it in sync with `sortTitle` on
    /// edit matters — that's the field sort actually runs on, and it has
    /// no UI of its own, so a manually retitled game would otherwise sort
    /// under its old name.
    private func commitTitle(_ newValue: String, for game: Game) {
        game.title = newValue
        game.sortTitle = newValue
        game.metadataManuallyEdited = true
        try? game.modelContext?.save()
    }

    /// Empty text commits as `nil` rather than `""`, matching how scraped/
    /// imported data represents "no value" — an editable field cleared out
    /// by the user should look the same as one that was never populated.
    private func commitOptionalText(_ newValue: String, to keyPath: ReferenceWritableKeyPath<Game, String?>, for game: Game) {
        game[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
        game.metadataManuallyEdited = true
        try? game.modelContext?.save()
    }
}
