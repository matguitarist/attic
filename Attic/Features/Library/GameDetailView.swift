import SwiftUI
import AtticLibraryScanning
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

/// Inspector contents for the selected game: a header (art, editable title,
/// actions) above a native grouped `Form`, so labels, fields and section
/// styling all come from the system.
struct GameDetailView: View {
    let game: Game?
    /// The system being browsed, summed up while no game is selected.
    var system: GameSystem? = nil
    /// Likewise the collection being browsed.
    var collection: GameCollection? = nil

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore
    @Environment(GameInfoEditor.self) private var infoEditor

    /// The description box grows into whatever height the panel has spare,
    /// which keeps Info and Play History at the bottom; it never goes below
    /// `minimumDescriptionHeight`, past which the panel just scrolls.
    @State private var descriptionHeight: CGFloat = Self.minimumDescriptionHeight
    private static let minimumDescriptionHeight: CGFloat = 120
    @State private var isEditingTitle = false

    var body: some View {
        if let game {
            Form {
                Section {
                    header(for: game)
                }

                Section("Info") {
                    editableRow("Developer", \.developer, for: game)
                    editableRow("Publisher", \.publisher, for: game)
                    editableRow("Genre", \.genre, for: game)
                    editableRow("Players", \.players, for: game)
                    if let releaseDate = game.releaseDate {
                        LabeledContent("Released", value: releaseDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)))
                    }
                    if let rating = game.rating, rating > 0 {
                        LabeledContent("Rating") {
                            StarRatingPicker(rating: .constant(rating))
                                .disabled(true)
                        }
                    }
                    LabeledContent("System", value: game.system?.displayName ?? game.systemCanonicalID)
                    DATVerdictRow(game: game)
                    MissingBIOSRow(game: game)
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

                DiscImageSection(game: game)

                Section("Description") {
                    // TextEditor has no Return-to-submit (Return is a
                    // newline), so this one commits on focus loss only.
                    CommitOnBlurField(
                        value: game.gameDescription ?? "",
                        onCommit: { commitOptionalText($0, to: \.gameDescription, for: game) }
                    ) { text, focus in
                        TextEditor(text: text)
                            .font(.callout)
                            .frame(height: descriptionHeight)
                            .scrollContentBackground(.hidden)
                            .focused(focus)
                    }
                    .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Spare room (positive) or overflow (negative).
                geometry.containerSize.height - geometry.contentSize.height
            } action: { _, slack in
                let target = max(Self.minimumDescriptionHeight, (descriptionHeight + slack).rounded(.down))
                // Ignore sub-point jitter so this settles instead of
                // nudging the layout back and forth.
                if abs(target - descriptionHeight) >= 1 {
                    descriptionHeight = target
                }
            }
            .modifier(BIOSSetDrop(game: game))
            // Fresh field state per game — see CommitOnBlurField.
            .id(game.persistentModelID)
        } else if let system {
            SystemOverviewView(system: system)
        } else if let collection {
            CollectionOverviewView(collection: collection)
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
            // The system's logo first, as in the system overview.
            if let logo = game.system?.systemID.logo {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 64)
                    .accessibilityLabel(game.system?.displayName ?? "")
                    .padding(.bottom, 4)
            }

            // A shot of the game itself (screenshot or title screen) reads
            // better at this size than box art, which the grid already
            // shows; box art is the fallback. 4:3 like the screens of most
            // of these systems, and GameCoverArtView fits rather than crops
            // anything shaped otherwise.
            GameHeaderMedia(imageURL: Self.headerImageURL(for: game), videoURL: game.previewVideoURL, title: game.title)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // A centered multi-line TextField only draws its first line, so
            // the title shows as wrapping Text and turns into a field when
            // clicked (Return or clicking away saves).
            if isEditingTitle {
                CommitOnBlurField(
                    value: game.title,
                    isValid: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    onCommit: { commitTitle($0, for: game) }
                ) { text, focus in
                    // Inside a Form, a TextField renders its title as a
                    // leading row label; the header wants just the name.
                    TextField("Title", text: text)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .focused(focus)
                        .onAppear { focus.wrappedValue = true }
                        .onChange(of: focus.wrappedValue) { _, focused in
                            if !focused { isEditingTitle = false }
                        }
                        .onSubmit { isEditingTitle = false }
                }
            } else {
                Text(game.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { isEditingTitle = true }
                    .help("Click to rename")
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
                Label(isRunningThisGame ? String(localized: "Running…") : String(localized: "Play"), systemImage: isRunningThisGame ? "gamecontroller.fill" : "play.fill")
                    .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(target == nil || isBusy)
            .help(target == nil ? String(localized: "Set a default emulator for this system in Settings, or choose one from Launch With.") : String(localized: "Play (⌘↩)"))

            Button {
                game.favorite.toggle()
                try? game.modelContext?.save()
            } label: {
                Label(game.favorite ? String(localized: "Unfavorite") : String(localized: "Favorite"), systemImage: game.favorite ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.large)
            .help(game.favorite ? String(localized: "Remove from Favorites (⌘D)") : String(localized: "Add to Favorites (⌘D)"))

            Button {
                infoEditor.game = game
            } label: {
                Label("Edit Info…", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.large)
            .help("Edit title, cover, release date, rating and more (⌘I)")

            if let manual = game.manualURL {
                Button {
                    NSWorkspace.shared.open(manual)
                } label: {
                    Label("Manual", systemImage: "book")
                        .labelStyle(.iconOnly)
                }
                .controlSize(.large)
                .help("Open the game's manual")
            }

            Menu {
                Menu("Launch With") {
                    LaunchWithMenuItems(game: game)
                }
                Menu("Scrape Info") {
                    ScrapeMenuItems(game: game)
                }
                .disabled(isScraping || (!screenScraperCredentialsStore.isConfigured && !theGamesDBCredentialsStore.isConfigured))
                AddToCollectionMenu(game: game)
                Button("Edit Info…") {
                    infoEditor.game = game
                }
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
            .help("Launch with a specific emulator, scrape info, edit info, or reveal the ROM")
        }
    }

    /// The game's screenshot, else its title screen, else its box art.
    /// Libraries scanned before screenshots were preferred stored the title
    /// screen, so look for an ES-DE screenshot next to it too — no rescan
    /// needed.
    static func headerImageURL(for game: Game) -> URL? {
        guard let titleScreen = game.titleScreenURL else { return game.coverArtURL }
        let folder = titleScreen.deletingLastPathComponent()
        if folder.lastPathComponent == "titlescreens" {
            let screenshots = folder.deletingLastPathComponent().appending(path: "screenshots", directoryHint: .isDirectory)
            let name = titleScreen.deletingPathExtension().lastPathComponent
            for ext in MediaFolder.imageExtensions {
                let candidate = screenshots.appending(path: "\(name).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return titleScreen
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
    private func editableRow(_ label: LocalizedStringKey, _ keyPath: ReferenceWritableKeyPath<Game, String?>, for game: Game) -> some View {
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

/// An arcade board's BIOS set (konamigx.zip) dropped on its game's panel
/// goes beside the game, where MAME and FinalBurn Neo look for it, and the
/// game is checked again.
private struct BIOSSetDrop: ViewModifier {
    let game: Game

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @State private var message: String?

    func body(content: Content) -> some View {
        let system = CanonicalSystemID(game.systemCanonicalID)
        if ToolsCoordinator.isArcade(system) {
            content
                .dropDestination(for: URL.self) { urls, _ in
                    add(urls, system: system)
                }
                .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
        } else {
            content
        }
    }

    private func add(_ urls: [URL], system: CanonicalSystemID) -> Bool {
        let sets = urls.filter { ArcadeBIOSSets.isBIOSSet($0.lastPathComponent, system: system) }
        guard !sets.isEmpty else {
            message = String(localized: "Only an arcade BIOS set (such as konamigx.zip) can be dropped on a game. Drop games on the list of games.")
            return false
        }
        let folder = game.romAbsoluteURL.deletingLastPathComponent()
        let added = sets.filter { BIOSSetLocating.copy($0, as: $0.lastPathComponent, into: [folder]) }.map(\.lastPathComponent)
        guard !added.isEmpty else {
            message = String(localized: "Couldn't copy \(sets.map(\.lastPathComponent).formatted(.list(type: .and))) to \(folder.lastPathComponent).")
            return false
        }
        message = String(localized: "Put with the games in \(folder.lastPathComponent): \(added.formatted(.list(type: .and))).")
        if game.datVerdict != nil {
            Task { _ = await tools.recheck(game, datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator) }
        }
        return true
    }
}

/// The BIOS set an arcade game was found to need, with Locate… to pick
/// it, wherever it is, and put it beside the game.
private struct MissingBIOSRow: View {
    let game: Game

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @State private var checking = false
    @State private var failed = false

    var body: some View {
        if let bios = game.datDetail.flatMap(SetProblems.init(json:))?.missingBIOS {
            LabeledContent("BIOS Set") {
                HStack {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(String(localized: "\(bios) missing"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Button("Locate…") { locate(bios) }
                        .buttonStyle(.link)
                        .disabled(checking)
                }
            }
            .help(String(localized: "The game boots from \(bios). Locate it and Attic puts a copy with the games, where the emulator looks for it."))
            .alert(String(localized: "Couldn't copy \(bios) to \(game.romAbsoluteURL.deletingLastPathComponent().lastPathComponent)."), isPresented: $failed) {}
        }
    }

    private func locate(_ bios: String) {
        guard let file = BIOSSetLocating.choose(bios) else { return }
        guard BIOSSetLocating.copy(file, as: bios, into: [game.romAbsoluteURL.deletingLastPathComponent()]) else {
            failed = true
            return
        }
        checking = true
        Task {
            _ = await tools.recheck(game, datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator)
            checking = false
        }
    }
}

/// What Tools › Verify Games found for the game, once it's been run:
/// against No-Intro's DAT, or for an arcade set its emulator's.
private struct DATVerdictRow: View {
    let game: Game

    private var isArcade: Bool { ToolsCoordinator.isArcade(CanonicalSystemID(game.systemCanonicalID)) }
    private var label: LocalizedStringKey { isArcade ? "Romset" : "No-Intro" }

    var body: some View {
        switch game.datVerdict {
        case "verified":
            LabeledContent(label) {
                Label("Verified", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            .help(isArcade ? String(localized: "Every chip, and disc image, its emulator's version expects.")
                           : game.datName.map { String(localized: "A good dump of \($0).") } ?? "")
        case "incomplete":
            LabeledContent(label) {
                HStack {
                    Label("Incomplete", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    DATDetailButton(game: game)
                }
            }
            .help(String(localized: "Chips or a disc image are missing: the game may not start."))
        case "differs":
            LabeledContent(label) {
                HStack {
                    Label(isArcade ? "Other Version" : "Differs", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    if isArcade { DATDetailButton(game: game) }
                }
            }
            .help(isArcade ? String(localized: "Some chips aren't the ones this emulator's version expects: the set comes from another version of MAME or FinalBurn Neo.")
                           : String(localized: "Named like a game No-Intro lists, but the data isn't that game's: a bad dump, a hack, or another revision."))
        case "unknown":
            LabeledContent(label) {
                Text("Not listed").foregroundStyle(.secondary)
            }
            .help(isArcade ? String(localized: "A set this emulator's version doesn't know by that name.")
                           : String(localized: "Homebrew, hacks, translations, prototypes, or dumps No-Intro doesn't list."))
        default:
            EmptyView()
        }
    }
}
