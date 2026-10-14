import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// What Tools › Verify Games found for a system's games, when it was run
/// and against which DATs, and a button to run it again. Shared by the
/// library's system overview and the system's help page.
struct SystemVerificationSection: View {
    let systemID: CanonicalSystemID
    /// The window the report shows in.
    let host: ToolsCoordinator.Host
    /// Queried rather than taken from the system, so verdicts saved by
    /// Verify Games show as soon as it's done.
    @Query private var games: [Game]

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @State private var showsRemoval = false

    init(systemID: CanonicalSystemID, host: ToolsCoordinator.Host) {
        self.systemID = systemID
        self.host = host
        let id = systemID.rawValue
        _games = Query(filter: #Predicate<Game> { $0.systemCanonicalID == id })
    }

    private var isArcade: Bool { ToolsCoordinator.isArcade(systemID) }

    var body: some View {
        let verdicts = Dictionary(grouping: games, by: { $0.datVerdict ?? "" }).mapValues(\.count)
        let verification = tools.verifications[systemID.rawValue]
        Section {
            if verification == nil, verdicts.keys.allSatisfy(\.isEmpty) {
                Text("Not verified yet.")
                    .foregroundStyle(.secondary)
            } else {
                row("Verified", systemImage: "checkmark.seal.fill", color: .green, count: verdicts["verified"])
                row("Incomplete", systemImage: "exclamationmark.triangle", color: .orange, count: verdicts["incomplete"])
                row(isArcade ? "Other Version" : "Differs", systemImage: "exclamationmark.triangle", color: .orange, count: verdicts["differs"])
                row("Not Listed", systemImage: "questionmark.circle", color: .secondary, count: verdicts["unknown"])
                row("Not Checked", systemImage: "circle", color: .secondary, count: verdicts[""])
            }
            HStack {
                Button(verification == nil ? String(localized: "Verify Games…") : String(localized: "Verify Again…")) {
                    Task {
                        await tools.verify(datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator,
                                           from: host, system: systemID)
                    }
                }
                .disabled(tools.isBusy || games.isEmpty)
                .help(isArcade ? String(localized: "Checks this system's sets against its emulator's DAT, and shows what's missing.")
                               : String(localized: "Checks this system's games against No-Intro's lists of known good dumps."))
                Button("Remove Games…") { showsRemoval = true }
                    .disabled(tools.isBusy || games.isEmpty)
                    .help("Moves games that aren't in the DAT, prototypes, demos, unlicensed games or hacks to the Trash.")
                if let activity = tools.activity, tools.reportHost == host {
                    ProgressView(value: activity.fraction ?? 0)
                        .frame(maxWidth: 120)
                }
            }
        } header: {
            Text("Verification")
                .sheet(isPresented: $showsRemoval) {
                    RemoveGamesView(systemName: SystemTaxonomy.definition(for: systemID)?.displayName ?? systemID.rawValue,
                                    isArcade: isArcade, games: games) { chosen in
                        Task {
                            await tools.trashGames(chosen, romsRoots: romsRootsStore.rootURLs, scanCoordinator: scanCoordinator, from: host)
                        }
                    }
                }
        } footer: {
            if let verification {
                Text(footer(verification))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// One verdict's row, left out when no game has it.
    @ViewBuilder
    private func row(_ title: LocalizedStringKey, systemImage: String, color: Color, count: Int?) -> some View {
        if let count, count > 0 {
            LabeledContent {
                Text(count.formatted()).monospacedDigit()
            } label: {
                Label(title, systemImage: systemImage).foregroundStyle(color)
            }
        }
    }

    private func footer(_ verification: ToolsCoordinator.Verification) -> String {
        let date = verification.date.formatted(date: .abbreviated, time: .shortened)
        guard !verification.dats.isEmpty else { return String(localized: "Last checked \(date).") }
        return String(localized: "Last checked \(date), against \(verification.dats.formatted(.list(type: .and))).")
    }
}

/// How complete a system's games are: their size on disk, and how many
/// have a cover, a screenshot, a video and a description.
struct SystemGamesSection: View {
    @Query private var games: [Game]
    @State private var bytes: Int64?

    init(systemID: CanonicalSystemID) {
        let id = systemID.rawValue
        _games = Query(filter: #Predicate<Game> { $0.systemCanonicalID == id })
    }

    var body: some View {
        Section("Your Games") {
            LabeledContent("Games", value: games.count.formatted())
            LabeledContent("On Disk") {
                if let bytes {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            coverage("Covers", games.count { $0.coverArtPath != nil })
            coverage("Screenshots", games.count { $0.titleScreenPath != nil })
            coverage("Videos", games.count { $0.videoPath != nil })
            coverage("Descriptions", games.count { !($0.gameDescription ?? "").isEmpty })
        }
        .task(id: games.count) {
            let files = games.map(\.romAbsoluteURL)
            bytes = await Task.detached(priority: .utility) {
                files.reduce(0) { $0 + LibraryStatsView.size(of: $1) }
            }.value
        }
    }

    /// "612 of 721", orange while some are missing.
    private func coverage(_ title: LocalizedStringKey, _ count: Int) -> some View {
        LabeledContent(title) {
            Text("\(count) of \(games.count)")
                .monospacedDigit()
                .foregroundStyle(count < games.count ? Color.orange : Color.secondary)
        }
    }
}

/// Picks games to move to the Trash by what they are: not in the DAT,
/// not matching it, or tagged as prototypes, demos, unlicensed, hacks or
/// bad dumps. Each can still be kept by unticking it.
struct RemoveGamesView: View {
    enum Reason: CaseIterable, Hashable {
        case notListed, differs, prototype, demo, unlicensed, hack, badDump
    }

    private struct Candidate: Identifiable {
        let game: GameToRemove
        let title: String
        let reasons: Set<Reason>
        var id: URL { game.rom }
    }

    let systemName: String
    let isArcade: Bool
    let onRemove: ([GameToRemove]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reasons: Set<Reason> = []
    @State private var kept: Set<URL> = []
    @State private var bytes: Int64?
    @State private var confirming = false
    private let candidates: [Candidate]

    init(systemName: String, isArcade: Bool, games: [Game], onRemove: @escaping ([GameToRemove]) -> Void) {
        self.systemName = systemName
        self.isArcade = isArcade
        self.onRemove = onRemove
        candidates = games.compactMap { game in
            var reasons: Set<Reason> = []
            switch game.datVerdict {
            case "unknown": reasons.insert(.notListed)
            case "differs": reasons.insert(.differs)
            default: break
            }
            for kind in DumpTags.kinds(of: (game.romRelativePath as NSString).lastPathComponent) {
                switch kind {
                case .prototype: reasons.insert(.prototype)
                case .demo: reasons.insert(.demo)
                case .unlicensed: reasons.insert(.unlicensed)
                case .hack: reasons.insert(.hack)
                case .badDump: reasons.insert(.badDump)
                }
            }
            guard !reasons.isEmpty else { return nil }
            return Candidate(game: GameToRemove(rom: game.romAbsoluteURL, systemFolder: game.systemFolderURL, relativePath: game.romRelativePath),
                             title: game.title, reasons: reasons)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var matching: [Candidate] { candidates.filter { !$0.reasons.isDisjoint(with: reasons) } }
    private var chosen: [GameToRemove] { matching.filter { !kept.contains($0.id) }.map(\.game) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remove Games").font(.title2.bold())
                Text(verbatim: systemName).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                Section {
                    ForEach(Reason.allCases, id: \.self) { reason in
                        let count = candidates.count { $0.reasons.contains(reason) }
                        if count > 0 {
                            Toggle(isOn: Binding(
                                get: { reasons.contains(reason) },
                                set: { if $0 { reasons.insert(reason) } else { reasons.remove(reason) } }
                            )) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title(reason))
                                        Text(detail(reason)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(count.formatted()).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    if candidates.isEmpty {
                        Text("Every game is a released one the DAT lists, or hasn't been verified yet.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Remove")
                } footer: {
                    Text("Not Listed and Differs come from the last Verify Games; the rest from the tags in file names, like (Proto), (Demo), (Unl) or [h1].")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !matching.isEmpty {
                    Section("Games") {
                        ForEach(matching) { candidate in
                            Toggle(isOn: Binding(
                                get: { !kept.contains(candidate.id) },
                                set: { if $0 { kept.remove(candidate.id) } else { kept.insert(candidate.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                    Text(verbatim: candidate.game.relativePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !chosen.isEmpty {
                    Group {
                        if let bytes {
                            Text("\(chosen.count) games, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                        } else {
                            Text("\(chosen.count) games")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash…") { confirming = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 560, height: 620)
        .task(id: chosen.map(\.rom)) {
            bytes = nil
            let roms = chosen.map(\.rom)
            bytes = await Task.detached(priority: .utility) {
                roms.reduce(Int64(0)) { total, rom in
                    FrontEndMedia.files(ofGame: rom).reduce(total) { $0 + FrontEndMedia.bytes(under: $1) }
                }
            }.value
        }
        .confirmationDialog("Move \(chosen.count) games to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) {
                let games = chosen
                dismiss()
                onRemove(games)
            }
        } message: {
            Text("Their files and media go to the Trash, and they leave the library with their play history. Put Back in the Trash restores the files.")
        }
    }

    private func title(_ reason: Reason) -> LocalizedStringKey {
        switch reason {
        case .notListed: isArcade ? "Not in the DAT" : "Not in No-Intro"
        case .differs: isArcade ? "Other versions" : "Differs from No-Intro"
        case .prototype: "Prototypes and betas"
        case .demo: "Demos and samples"
        case .unlicensed: "Unlicensed, pirate and homebrew"
        case .hack: "Hacks"
        case .badDump: "Bad dumps"
        }
    }

    private func detail(_ reason: Reason) -> LocalizedStringKey {
        switch reason {
        case .notListed: isArcade ? "Sets the emulator's version doesn't know by that name." : "Homebrew, hacks, translations or dumps No-Intro doesn't list."
        case .differs: isArcade ? "Sets with chips from another emulator version." : "Named like a listed game, with other data: bad dumps or other revisions."
        case .prototype: "(Proto), (Beta), (Alpha)"
        case .demo: "(Demo), (Sample), (Kiosk)"
        case .unlicensed: "(Unl), (Pirate), (Aftermarket), (Homebrew)"
        case .hack: "(Hack), [h]"
        case .badDump: "[b]"
        }
    }
}
