import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

/// The inspector while a system is shown and no game is selected: the
/// system's logo, how it's played, and its play history.
struct SystemOverviewView: View {
    let system: GameSystem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(SystemSettingsEditor.self) private var systemSettingsEditor
    @Environment(HelpNavigator.self) private var helpNavigator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(EmulatorSetupCoordinator.self) private var setup
    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]
    /// Bumped when Attic comes back to the front, so BIOS files dropped in
    /// from the Finder show up as found.
    @State private var biosCheck = 0

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    if let logo = system.systemID.logo {
                        logo
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 120)
                            .accessibilityLabel(system.displayName)
                    }
                    VStack(spacing: 2) {
                        Text(system.displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        if let summary = SystemFacts.summary(for: system.systemID) {
                            Text(verbatim: summary)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(system.gameCount) games")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // No working emulator yet: offer the recommended ones first.
            if !setup.status(of: system, retroArchStore: retroArchStore, profiles: profiles).isReady {
                Section {
                    EmulatorSuggestionView(system: system, showsBackground: false)
                }
            }

            Section {
                LabeledContent("Emulator", value: emulatorName ?? String(localized: "None chosen"))
                Button("System Settings…") { systemSettingsEditor.system = system }
                ScrapeSelectionButton(title: "Scrape This System", selection: .system(system.systemID))
                Button("About This System") {
                    helpNavigator.open(.system(system.systemID), with: openWindow)
                }
            }

            if system.gameCount > 0 {
                SystemGamesSection(systemID: system.systemID)
            }

            if ToolsCoordinator.canVerify(system.systemID), system.gameCount > 0 {
                SystemVerificationSection(systemID: system.systemID, host: .library)
            }

            informationSection

            if !biosRequirements.isEmpty {
                biosSection
            }

            Section("Play History") {
                LabeledContent("Games Played", value: "\(history.played)")
                LabeledContent("Favorites", value: "\(history.favorites)")
                if history.playtime > 0 {
                    LabeledContent("Total Playtime", value: Self.formattedPlaytime(history.playtime))
                }
                if let last = history.lastPlayed {
                    LabeledContent("Last Played") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(last.title)
                            if let date = last.lastPlayedDate {
                                Text(date.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Text("Select a game to see its details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .task {
            // PS2 dumps dropped into BIOS/ itself go where PCSX2 looks.
            if emulationFolderStore.folder.movePS2BIOSIntoPlace().count > 0 { biosCheck += 1 }
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                emulationFolderStore.folder.movePS2BIOSIntoPlace()
                biosCheck += 1
            }
        }
    }

    // MARK: - Information

    @ViewBuilder
    private var informationSection: some View {
        let definition = SystemTaxonomy.definition(for: system.systemID)
        let extensions = SystemFacts.fileExtensions(for: system.systemID, coreInfo: emulationFolderStore.folder.coreInfo)
        let info = SystemHelpContent.info(for: system.systemID)
        if definition != nil || !extensions.isEmpty || info != nil {
            Section("Information") {
                // Label above, value below: these run long, and beside the
                // label they wrapped differently from one system to the next.
                if let definition {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROM Folder")
                        Text(SystemFacts.romFolderNames(definition))
                            .monospaced()
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if !extensions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("File Types")
                        // One tag per extension, so a line only ever breaks
                        // between two of them.
                        TagList(items: extensions.map { ".\($0)" })
                    }
                }
                if let info {
                    Link(destination: info.wikipediaURL) {
                        Label("Wikipedia", systemImage: "safari")
                    }
                }
            }
        }
    }

    // MARK: - BIOS

    /// What the system's chosen emulator needs. Attic only checks for
    /// these; they're dumped from hardware the user owns.
    private var biosRequirements: [BIOSRequirement] {
        EmulatorSetupCoordinator.biosRequirements(for: system)
    }

    private var biosSection: some View {
        Section {
            let _ = biosCheck
            ForEach(biosRequirements.statuses(in: emulationFolderStore.folder.bios)) { file in
                BIOSFileRow(file: file) { biosCheck += 1 }
            }
            Button("Show BIOS Folder") {
                BIOSFileRow.showFolder(for: biosRequirements, bios: emulationFolderStore.folder.bios)
            }
        } header: {
            Text("BIOS")
        } footer: {
            Text("Dump BIOS files from hardware you own; Attic never downloads them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var history: (played: Int, favorites: Int, playtime: Double, lastPlayed: Game?) {
        let games = system.games
        return (
            games.count { $0.playCount > 0 },
            games.count(where: \.favorite),
            games.reduce(0) { $0 + $1.totalPlaytimeSeconds },
            games.filter { $0.lastPlayedDate != nil }.max { $0.lastPlayedDate! < $1.lastPlayedDate! }
        )
    }

    private var emulatorName: String? {
        system.emulatorName(retroArchStore: retroArchStore, modelContext: modelContext)
    }

    static func formattedPlaytime(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}

extension GameSystem {
    /// What runs this system's games when they have no override:
    /// "RetroArch (Snes9x)", "DuckStation" or a custom profile's name.
    @MainActor
    func emulatorName(retroArchStore: RetroArchSettingsStore, modelContext: ModelContext) -> String? {
        switch defaultLaunchTarget {
        case .retroArchCore(let identifier):
            let core = retroArchStore.core(withIdentifier: identifier)?.displayName
                ?? EmulatorCatalog.recommendation(for: systemID)?.cores.first { $0.coreIdentifier == identifier }?.displayName
                ?? identifier
            return String(localized: "RetroArch (\(core))")
        case .emulatorProfile(let id):
            let descriptor = FetchDescriptor<EmulatorProfile>(predicate: #Predicate { $0.id == id })
            return (try? modelContext.fetch(descriptor).first)?.name
        case nil:
            return nil
        }
    }
}

/// Short values (file types, BIOS file names) as small tags that wrap
/// between each other, never inside one.
struct TagList: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(items, id: \.self) { Tag($0) }
        }
    }
}

/// One file name, extension or model, set apart as a small tag.
struct Tag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .monospaced()
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: .rect(cornerRadius: 4))
            .textSelection(.enabled)
    }
}

/// Lays its subviews out left to right, starting a new line when the next
/// one wouldn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.reduce(0) { $0 + $1.width } + spacing * CGFloat(max($0.count - 1, 0)) }.max() ?? 0
        let height = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var index = 0
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += (row.map(\.height).max() ?? 0) + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        return rows
    }
}

/// A BIOS file next to the known good dumps of it: size and MD5, the
/// differences marked.
struct BIOSComparisonView: View {
    let file: BIOSFileStatus

    var body: some View {
        let check = file.check
        VStack(alignment: .leading, spacing: 12) {
            Text("\(file.fileName) isn't a known dump").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Size").foregroundStyle(.secondary)
                    Text("MD5").foregroundStyle(.secondary)
                }
                .font(.caption)
                GridRow {
                    Text("Yours").bold()
                    Text(size(check.size))
                        .foregroundStyle(check.expected.contains { $0.size == check.size } ? Color.primary : .orange)
                    Text(verbatim: check.md5 ?? "—").foregroundStyle(.orange)
                }
                ForEach(check.expected, id: \.self) { entry in
                    GridRow {
                        Text("Expected").bold()
                        Text(size(entry.size))
                        Text(verbatim: entry.md5)
                    }
                }
            }
            .font(.callout.monospaced())
            .textSelection(.enabled)
            Text(explanation(check))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let url = file.url {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Spacer()
                if let md5 = check.md5 {
                    Button("Copy MD5") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md5, forType: .string)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private func size(_ bytes: Int?) -> String {
        bytes.map { "\($0.formatted()) B" } ?? "—"
    }

    private func explanation(_ check: BIOSChecksums.Check) -> String {
        if let size = check.size, !check.expected.contains(where: { $0.size == size }) {
            return String(localized: "The size differs too: it's likely another file, a damaged copy, or a dump with something added. Dump it again, or look for the expected one.")
        }
        return String(localized: "Same size, other data: most likely another revision of this BIOS, sometimes a damaged copy. It may still work; if games don't start, use the expected dump.")
    }
}

/// One BIOS file's row: its name, whether it's required, and whether
/// it's there. Shared by the system panel and Settings › BIOS.
struct BIOSFileRow: View {
    let file: BIOSFileStatus
    /// After a misnamed dump was put in place, so the list checks again.
    var onChange: () -> Void = {}
    @State private var copyFailed = false
    @State private var showsComparison = false

    var body: some View {
        LabeledContent {
            if file.isPresent {
                switch file.verdict {
                case .verified:
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .help("A known good dump.")
                case .unrecognized:
                    HStack {
                        Label("Not a known dump", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .help("Named right, but it isn't one of the known good dumps: another revision, or a bad dump. It may still work; if games don't start, try another dump.")
                        Button("Compare…") { showsComparison = true }
                            .popover(isPresented: $showsComparison, arrowEdge: .bottom) {
                                BIOSComparisonView(file: file)
                            }
                    }
                case .unchecked:
                    Label("Found", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else if let misnamed = file.misnamed, let target = file.expectedURL {
                HStack {
                    Text("Found as \(misnamed.lastPathComponent)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(copyFailed ? String(localized: "Couldn't Copy") : String(localized: "Use It")) {
                        copyFailed = !Self.copy(misnamed, to: target)
                        if !copyFailed { onChange() }
                    }
                    .help("Copies it in under the name the emulator looks for. The file you have stays as it is.")
                }
            } else {
                Label("Missing", systemImage: file.required ? "exclamationmark.triangle.fill" : "circle")
                    .foregroundStyle(file.required ? .orange : .secondary)
            }
        } label: {
            Tag(file.fileName)
            Text([file.required ? String(localized: "Required") : String(localized: "Optional"), file.note]
                .compactMap { $0 }
                .joined(separator: " · "))
            checksum
        }
    }

    /// The file's MD5, or the one it should have: both when they differ.
    @ViewBuilder
    private var checksum: some View {
        let check = file.check
        let expected = check.expected.first?.md5
        let more = check.expected.count > 1 ? String(localized: " (or \(check.expected.count - 1) other known dumps)") : ""
        switch (file.isPresent, check.verdict) {
        case (true, .verified):
            Text(verbatim: "MD5 \(expected ?? check.md5 ?? "")")
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .help(check.hasHeader ? String(localized: "The known dump's checksum: the file has a 512-byte header before it.") : String(localized: "The known dump's checksum, which the file has."))
        case (true, .unrecognized):
            if let expected {
                Text(String(localized: "Expected MD5 \(expected)") + more)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let md5 = check.md5 {
                Text(String(localized: "Found MD5 \(md5)"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        case (true, .unchecked):
            if let md5 = check.md5 {
                Text(verbatim: "MD5 \(md5)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        case (false, _):
            if let expected {
                Text(String(localized: "Expected MD5 \(expected)") + more)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private static func copy(_ file: URL, to target: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: target)
            return true
        } catch {
            return false
        }
    }

    /// Opens where the system's files go, which isn't always BIOS/ itself:
    /// the first missing required file's folder, else the first file's.
    static func showFolder(for requirements: [BIOSRequirement], bios: URL) {
        guard let requirement = requirements.first(where: { $0.required && !$0.isPresent(in: bios) }) ?? requirements.first else { return }
        let folder = requirement.folder(in: bios)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
