import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticLibraryScanning
import AtticEmulation

/// What Tools › Verify Games found for a system's games, in one row of
/// tags; the breakdown, each verdict's games and Verify Again are in a
/// popover. Shared by the library's system overview and the system's
/// help page.
struct SystemVerificationSection: View {
    let systemID: CanonicalSystemID
    /// The window the report shows in.
    let host: ToolsCoordinator.Host
    /// Queried rather than taken from the system, so verdicts saved by
    /// Verify Games show as soon as it's done.
    @Query private var games: [Game]

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @State private var showsDetails = false
    @State private var coverage: DATCoverage?

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
            if let coverage {
                DATCoverageRow(coverage: coverage)
            }
            if ToolsCoordinator.canVerify(systemID), coverage?.isCheckable ?? true {
            LabeledContent {
                Button("Details…") { showsDetails = true }
                    .popover(isPresented: $showsDetails, arrowEdge: .leading) {
                        VerificationDetails(systemID: systemID, host: host, games: games, verdicts: verdicts, verification: verification)
                    }
            } label: {
                if verdicts.keys.allSatisfy(\.isEmpty) {
                    Text("Not verified yet")
                        .foregroundStyle(Color.secondaryText)
                } else {
                    FlowLayout(spacing: 4) {
                        if let n = verdicts["verified"] {
                            StatusTag(text: String(localized: "\(n) verified"), systemImage: "checkmark.seal.fill", tint: .green)
                        }
                        if let n = verdicts["incomplete"] {
                            StatusTag(text: String(localized: "\(n) incomplete"), systemImage: "exclamationmark.triangle.fill", tint: .orange)
                        }
                        if let n = verdicts["differs"] {
                            StatusTag(text: isArcade ? String(localized: "\(n) other version") : String(localized: "\(n) differ"),
                                      systemImage: "exclamationmark.triangle.fill", tint: .orange)
                        }
                        if let n = verdicts["unknown"] {
                            StatusTag(text: String(localized: "\(n) not listed"), tint: .secondary)
                        }
                        if let n = verdicts[""] {
                            StatusTag(text: String(localized: "\(n) not checked"), tint: .secondary)
                        }
                    }
                }
            }
            if let activity = tools.activity, tools.reportHost == host {
                ProgressView(value: activity.fraction ?? 0)
            }
            }
        } header: {
            Text("Verification")
        } footer: {
            if let verification {
                Text(Self.footer(verification))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        // Read again for another system, and after a verify, which may
        // have downloaded one.
        .task(id: "\(systemID.rawValue) \(verification?.date.timeIntervalSince1970 ?? 0)") {
            coverage = nil
            let id = systemID
            let source = ToolsCoordinator.arcadeSource(for: id)
            let folder = emulationFolderStore.folder.dats
            coverage = await Task.detached(priority: .utility) {
                DATCoverage.coverage(for: id, isArcade: ToolsCoordinator.isArcade(id), arcadeSource: source, datsFolder: folder)
            }.value
        }
    }

    static func footer(_ verification: ToolsCoordinator.Verification) -> String {
        let date = verification.date.formatted(date: .abbreviated, time: .shortened)
        guard !verification.dats.isEmpty else { return String(localized: "Last checked \(date).") }
        return String(localized: "Last checked \(date), against \(verification.dats.formatted(.list(type: .and))).")
    }
}

/// The popover behind a system's Verification row: each verdict's count
/// and games, when it was checked, and Verify Again.
private struct VerificationDetails: View {
    let systemID: CanonicalSystemID
    let host: ToolsCoordinator.Host
    let games: [Game]
    let verdicts: [String: Int]
    let verification: ToolsCoordinator.Verification?

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(\.dismiss) private var dismiss

    private var isArcade: Bool { ToolsCoordinator.isArcade(systemID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verification").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                row("Verified", "checkmark.seal.fill", .green, verdicts["verified"])
                row("Incomplete", "exclamationmark.triangle.fill", .orange, verdicts["incomplete"], verdict: "incomplete")
                row(isArcade ? "Other Version" : "Differs", "exclamationmark.triangle.fill", .orange, verdicts["differs"], verdict: "differs")
                row("Not Listed", "questionmark.circle", .secondary, verdicts["unknown"])
                row("Not Checked", "circle", .secondary, verdicts[""])
            }
            if let verification {
                Text(SystemVerificationSection.footer(verification))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(verification == nil ? String(localized: "Verify Games…") : String(localized: "Verify Again…")) {
                    dismiss()
                    Task {
                        await tools.verify(datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator,
                                           from: host, system: systemID)
                    }
                }
                .disabled(tools.isBusy || games.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// One verdict's row, left out when no game has it; Show lists the
    /// games and what's wrong with each.
    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ image: String, _ tint: Color, _ count: Int?, verdict: String? = nil) -> some View {
        if let count, count > 0 {
            GridRow {
                Image(systemName: image).foregroundStyle(tint)
                Text(title)
                Spacer()
                if let verdict {
                    DATGamesButton(games: games.filter { $0.datVerdict == verdict })
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
                Text(count.formatted())
                    .monospacedDigit()
                    .gridColumnAlignment(.trailing)
            }
        }
    }
}

/// Remove Games for a system, as a sheet: shared by the system panel's
/// Actions menu and anything else that offers it.
struct RemoveGamesSheet: ViewModifier {
    @Binding var isPresented: Bool
    let systemID: CanonicalSystemID
    let host: ToolsCoordinator.Host

    @Query private var games: [Game]
    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(RomsRootsStore.self) private var romsRootsStore

    init(isPresented: Binding<Bool>, systemID: CanonicalSystemID, host: ToolsCoordinator.Host) {
        _isPresented = isPresented
        self.systemID = systemID
        self.host = host
        let id = systemID.rawValue
        _games = Query(filter: #Predicate<Game> { $0.systemCanonicalID == id })
    }

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            RemoveGamesView(systemName: SystemTaxonomy.definition(for: systemID)?.displayName ?? systemID.rawValue,
                            isArcade: ToolsCoordinator.isArcade(systemID), games: games) { chosen in
                Task {
                    await tools.trashGames(chosen, system: systemID, romsRoots: romsRootsStore.rootURLs, scanCoordinator: scanCoordinator, from: host)
                }
            }
        }
    }
}

/// A system's games at a glance: how many, their size, how much they've
/// been played, and how many have each kind of media.
struct SystemGamesSection: View {
    @Query private var games: [Game]
    @State private var bytes: Int64?

    init(systemID: CanonicalSystemID) {
        let id = systemID.rawValue
        _games = Query(filter: #Predicate<Game> { $0.systemCanonicalID == id })
    }

    var body: some View {
        let playtime = games.reduce(0) { $0 + $1.totalPlaytimeSeconds }
        Section("Your Games") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatTile(value: games.count.formatted(), label: "Games")
                StatTile(value: bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…", label: "On Disk")
                StatTile(value: games.count(where: { $0.playCount > 0 }).formatted(), label: "Played")
                StatTile(value: playtime > 0 ? SystemOverviewView.formattedPlaytime(playtime) : "—", label: "Play Time")
            }
            .padding(.vertical, 2)
            // How many have each kind of media, orange while some lack it.
            let counts = [games.count { $0.coverArtPath != nil }, games.count { $0.titleScreenPath != nil },
                          games.count { $0.videoPath != nil }, games.count { !($0.gameDescription ?? "").isEmpty }]
            // Two columns while every count is whole; "719/721" needs the width.
            let columns = counts.allSatisfy { $0 == games.count } ? 2 : 1
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), alignment: .leading, spacing: 6) {
                coverage("photo", "Covers", counts[0])
                coverage("tv", "Screenshots", counts[1])
                coverage("film", "Videos", counts[2])
                coverage("text.alignleft", "Descriptions", counts[3])
            }
            .padding(.vertical, 2)
            if let last = games.filter({ $0.lastPlayedDate != nil }).max(by: { $0.lastPlayedDate! < $1.lastPlayedDate! }) {
                LabeledContent("Last Played") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(last.title)
                        if let date = last.lastPlayedDate {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
            }
        }
        .task(id: games.count) {
            let files = games.map(\.romAbsoluteURL)
            bytes = await Task.detached(priority: .utility) {
                files.reduce(0) { $0 + LibraryStatsView.size(of: $1) }
            }.value
        }
    }

    private func coverage(_ image: String, _ label: LocalizedStringKey, _ count: Int) -> some View {
        let complete = count == games.count
        return HStack(spacing: 6) {
            Image(systemName: image)
                .frame(width: 16)
                .foregroundStyle(complete ? Color.secondaryText : .orange)
            Text(label)
            Spacer(minLength: 4)
            Text(verbatim: complete ? count.formatted() : "\(count)/\(games.count)")
                .monospacedDigit()
                .foregroundStyle(complete ? Color.secondaryText : .orange)
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
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

/// What Verify Games found wrong with a game, as a list: "2 ROMs missing:
/// a.c1 and b.c2 (in x.zip)", one line per problem.
private func detailLines(_ detail: String) -> [String] {
    // "set: problem; problem"
    let problems = detail.firstRange(of: ": ").map { String(detail[$0.upperBound...]) } ?? detail
    return problems.components(separatedBy: "; ")
}

/// "Details" beside a game's verdict: what's missing or from another
/// version. Saved by Verify Games; for a game verified before details
/// were saved, the game is checked again on its own.
struct DATDetailButton: View {
    let game: Game

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @State private var shows = false
    @State private var checking = false

    var body: some View {
        Button("Details") { shows = true }
            .buttonStyle(.link)
            .popover(isPresented: $shows, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: game.romAbsoluteURL.lastPathComponent).font(.headline)
                    if let detail = game.datDetail {
                        SavedDATDetail(detail: detail)
                    } else if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Nothing more to say: the set's chips all match.")
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                .padding(16)
                .frame(width: 520, alignment: .leading)
                .task {
                    guard game.datDetail == nil else { return }
                    checking = true
                    _ = await tools.recheck(game, datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator)
                    checking = false
                }
            }
    }
}

/// A verdict's games in the system's Verification section, each with
/// what's wrong with it.
struct DATGamesButton: View {
    let games: [Game]
    @State private var shows = false

    var body: some View {
        Button("Show") { shows = true }
            .buttonStyle(.link)
            .popover(isPresented: $shows, arrowEdge: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { game in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(game.title).bold()
                                Text(verbatim: game.romAbsoluteURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let detail = game.datDetail {
                                    SavedDATDetail(detail: detail)
                                } else if game.datVerdict != "differs" || ToolsCoordinator.isArcade(CanonicalSystemID(game.systemCanonicalID)) {
                                    Text("Verify Again, or open the game's Details, to see what's wrong.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(width: 520, alignment: .leading)
                }
                .frame(maxHeight: 520)
            }
    }
}

/// A game's saved verify details: a table when they were saved file by
/// file, else their text, a line per problem.
struct SavedDATDetail: View {
    let detail: String

    var body: some View {
        if let problems = SetProblems(json: detail) {
            SetProblemsView(problems: problems)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(detailLines(detail), id: \.self) { line in
                    Text(line)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// What's wrong with an arcade set, as tables: each file, the checksum
/// the DAT lists, and the one yours has.
struct SetProblemsView: View {
    let problems: SetProblems

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bios = problems.missingBIOS {
                Label {
                    Text("BIOS set \(bios) missing")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.orange)
            }
            table("From Another Version", problems.otherVersionROMs, checksum: "CRC32", showsFound: true)
            table("Missing", problems.missingROMs, checksum: "CRC32", showsFound: false)
            if !problems.missingROMsIn.isEmpty {
                Text("The missing ROMs are in \(problems.missingROMsIn.formatted(.list(type: .and))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            table("Disc Images From Another Version", problems.otherVersionDisks, checksum: "SHA-1", showsFound: true)
            table("Disc Images Missing", problems.missingDisks, checksum: "SHA-1", showsFound: false)
            Text("Checked against \(problems.dat).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func table(_ title: LocalizedStringKey, _ files: [SetProblems.File], checksum: String, showsFound: Bool) -> some View {
        if !files.isEmpty, checksum == "SHA-1" {
            // Too long for columns side by side: one under the other.
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold())
                ForEach(files, id: \.self) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: file.name).font(.callout.monospaced())
                        Text(verbatim: "SHA-1 \(file.expected)").foregroundStyle(.green)
                        if let found = file.found {
                            Text("Yours \(found)").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.monospaced())
                }
            }
        } else if !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.bold())
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("File")
                        Text(verbatim: checksum)
                        if showsFound { Text("Yours") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(files, id: \.self) { file in
                        GridRow {
                            Text(verbatim: file.name)
                            Text(verbatim: file.expected).foregroundStyle(.green)
                            if showsFound { Text(verbatim: file.found ?? "—").foregroundStyle(.orange) }
                        }
                    }
                }
                .font(.callout.monospaced())
            }
        }
    }
}

/// "Details" in the verify report, beside a set's one-line summary.
struct SetProblemsButton: View {
    let problems: SetProblems
    @State private var shows = false

    var body: some View {
        Button("Details") { shows = true }
            .buttonStyle(.link)
            .popover(isPresented: $shows, arrowEdge: .bottom) {
                ScrollView {
                    SetProblemsView(problems: problems)
                        .padding(16)
                        .frame(width: 520, alignment: .leading)
                }
                .frame(maxHeight: 520)
            }
    }
}

/// Which DAT a system's games are checked against, and whether it's
/// there: "No-Intro · Nintendo - Game Boy, Oct 12, 2026".
struct DATCoverageRow: View {
    let coverage: DATCoverage

    var body: some View {
        LabeledContent {
            status
        } label: {
            HStack(spacing: 6) {
                Text("DAT")
                StatusTag(text: kindName, tint: .accentColor)
            }
            if let detail {
                Text(verbatim: detail)
                    .lineLimit(3)
            }
        }
    }

    private var kindName: String {
        switch coverage.kind {
        case .noIntro: "No-Intro"
        case .redump: "Redump"
        case .mame: "MAME"
        case .fbneo: "FinalBurn Neo"
        case .none: String(localized: "None")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch coverage.status {
        case .present:
            StatusTag(text: String(localized: "Present"), systemImage: "checkmark.circle.fill", tint: .green)
        case .missing:
            VStack(alignment: .trailing, spacing: 4) {
                StatusTag(text: String(localized: "Missing"), systemImage: "exclamationmark.triangle.fill", tint: .orange)
                if coverage.kind == .noIntro {
                    Link("DAT-o-MATIC", destination: URL(string: "https://datomatic.no-intro.org/index.php?page=download")!)
                        .font(.caption)
                }
            }
        case .incompatible:
            StatusTag(text: String(localized: "Not compatible"), systemImage: "exclamationmark.circle", tint: .orange)
        case .notSupported:
            StatusTag(text: String(localized: "Not checked yet"), tint: .secondary)
        case .notApplicable:
            StatusTag(text: String(localized: "Not listed"), tint: .secondary)
        }
    }

    private var detail: String? {
        switch coverage.status {
        case .present(let names, let date):
            let list = names.formatted(.list(type: .and))
            return date.map { "\(list), \($0.formatted(date: .abbreviated, time: .omitted))" } ?? list
        case .missing:
            switch coverage.kind {
            case .noIntro: return String(localized: "Add its DAT from DAT-o-MATIC to the DATs folder.")
            case .mame, .fbneo: return String(localized: "Verify Games offers to download it.")
            default: return nil
            }
        case .incompatible(let names):
            return String(localized: "Only DATs for something else: \(names.formatted(.list(type: .and))).")
        case .notSupported:
            return String(localized: "Disc images aren't verified yet.")
        case .notApplicable:
            return String(localized: "No DAT lists these games: hacks, ports and engines.")
        }
    }
}
