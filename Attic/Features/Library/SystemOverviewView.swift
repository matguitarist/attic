import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation
import AtticLibraryScanning

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
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]
    /// Bumped when Attic comes back to the front, so BIOS files dropped in
    /// from the Finder show up as found.
    @State private var biosCheck = 0
    @State private var showsBIOS = false
    @State private var showsRemoval = false
    /// Bumped when the logo changes.
    @State private var logoCheck = 0

    private var canVerify: Bool { ToolsCoordinator.canVerify(system.systemID) && system.gameCount > 0 }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    let _ = logoCheck
                    if let logo = system.logo {
                        logo
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220, maxHeight: 96)
                            .accessibilityLabel(system.displayName)
                            .contextMenu { logoMenu }
                            .help("Right-click to use your own logo, or drop a picture on it")
                    } else {
                        Button("Add Logo…") { chooseLogo() }
                            .controlSize(.small)
                    }
                    VStack(spacing: 2) {
                        Text(system.displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        if let summary = SystemFacts.summary(for: system.systemID) {
                            Text(verbatim: summary)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                // A picture dropped here becomes the system's logo.
                .dropDestination(for: URL.self) { urls, _ in
                    guard let picture = urls.first(where: SystemArtRow.isPicture) else { return false }
                    setLogo(picture)
                    return true
                }
            }

            Section {
                SystemArtRow(system: system, art: .fanart, title: "Fan Art",
                             help: "A wallpaper behind the system in Cabinet Mode")
                SystemArtRow(system: system, art: .picture, title: "Picture",
                             help: "The console itself, on Cabinet Mode's systems")
                SystemArtRow(system: system, art: .video, title: "Video",
                             help: "Plays in place of the picture after a moment")
            } header: {
                Text("Pictures and Video")
            } footer: {
                Text("Kept in the system's Media folder, beside its games' media. Drop a picture on a row to use it.")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }

            // No working emulator yet: offer the recommended ones first.
            if !setup.status(of: system, retroArchStore: retroArchStore, profiles: profiles).isReady {
                Section {
                    EmulatorSuggestionView(system: system, showsBackground: false)
                }
            }

            Section {
                LabeledContent("Emulator", value: emulatorName ?? String(localized: "None chosen"))
                HStack {
                    Button("System Settings…") { systemSettingsEditor.system = system }
                    Spacer()
                    actionsMenu
                }
            }

            if system.gameCount > 0 {
                SystemGamesSection(systemID: system.systemID)
            }

            // The DAT row for every system with games; verdicts where
            // its games can be verified.
            if system.gameCount > 0 {
                SystemVerificationSection(systemID: system.systemID, host: .library)
            }

            if !biosRequirements.isEmpty {
                biosSection
            }
        }
        .formStyle(.grouped)
        .modifier(RemoveGamesSheet(isPresented: $showsRemoval, systemID: system.systemID, host: .library))
        .task {
            // PS2 dumps dropped into BIOS/ itself go where PCSX2 looks.
            if emulationFolderStore.folder.movePS2BIOSIntoPlace().count > 0 { biosCheck += 1 }
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                emulationFolderStore.folder.movePS2BIOSIntoPlace()
                biosCheck += 1
            }
        }
    }

    @ViewBuilder
    private var logoMenu: some View {
        Button("Choose Logo…") { chooseLogo() }
        if let own = system.ownArt(.logo) {
            Button("Show Logo in Finder") { NSWorkspace.shared.activateFileViewerSelecting([own]) }
            Button("Use Attic's Logo") { setLogo(nil) }
        }
    }

    private func chooseLogo() {
        SystemArtRow.choose(message: String(localized: "A logo with a transparent background looks best: PNG, HEIC or WebP.")) { setLogo($0) }
    }

    /// Into the system's media folder, where Cabinet Mode and the library
    /// both find it; nil goes back to Attic's.
    private func setLogo(_ picture: URL?) {
        SystemArtRow.set(.logo, to: picture, for: system)
        logoCheck += 1
    }

    /// Everything else to do with the system, in one menu rather than a
    /// column of buttons.
    private var actionsMenu: some View {
        Menu {
            Button("Refresh This System", systemImage: "arrow.clockwise") {
                Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs, only: [system.systemID]) }
            }
            .disabled(scanCoordinator.state == .scanning)
            ScrapeSelectionMenu(title: "Scrape This System", selection: .system(system.systemID))
            if canVerify {
                Divider()
                Button("Verify Games…", systemImage: "checkmark.seal") {
                    Task { await tools.verify(datsFolder: emulationFolderStore.folder.dats, scanCoordinator: scanCoordinator, from: .library, system: system.systemID) }
                }
                .disabled(tools.isBusy)
                if ToolsCoordinator.isArcade(system.systemID) {
                    Button("Rebuild Sets…", systemImage: "shippingbox") {
                        let folder = system.romsRootURL
                        Task { await tools.analyzeRebuild(system: system.systemID, folder: folder, datsFolder: emulationFolderStore.folder.dats, from: .library) }
                    }
                    .disabled(tools.isBusy)
                }
                Button("Remove Games…", systemImage: "trash") { showsRemoval = true }
                    .disabled(tools.isBusy)
            }
            Divider()
            Button("About This System", systemImage: "info.circle") {
                helpNavigator.open(.system(system.systemID), with: openWindow)
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .fixedSize()
        .help("Refresh, scrape, verify or clean up this system's games")
    }

    // MARK: - BIOS

    /// What the system's chosen emulator needs. Attic only checks for
    /// these; they're dumped from hardware the user owns.
    private var biosRequirements: [BIOSRequirement] {
        EmulatorSetupCoordinator.biosRequirements(for: system)
    }

    /// One row of tags; each file, its MD5 and state are in a popover.
    private var biosSection: some View {
        let _ = biosCheck
        let files = biosRequirements.statuses(in: emulationFolderStore.folder.bios)
        let verified = files.count { $0.isPresent && $0.verdict == .verified }
        let found = files.count { $0.isPresent && $0.verdict == .unchecked }
        let unknown = files.count { $0.isPresent && $0.verdict == .unrecognized }
        let missing = files.count { !$0.isPresent && $0.required }
        let optional = files.count { !$0.isPresent && !$0.required }
        return Section {
            LabeledContent {
                Button("Details…") { showsBIOS = true }
                    .popover(isPresented: $showsBIOS, arrowEdge: .leading) {
                        VStack(alignment: .leading, spacing: 0) {
                            Form {
                                ForEach(files) { file in
                                    BIOSFileRow(file: file) { biosCheck += 1 }
                                }
                            }
                            .formStyle(.grouped)
                            HStack {
                                Text("Dump BIOS files from hardware you own; Attic never downloads them.")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText)
                                Spacer()
                                Button("Show BIOS Folder") {
                                    BIOSFileRow.showFolder(for: biosRequirements, bios: emulationFolderStore.folder.bios)
                                }
                            }
                            .padding([.horizontal, .bottom], 16)
                        }
                        // Rows with two checksums (a dump that isn't a known
                        // one, or a missing file) are taller.
                        .frame(width: 500, height: min(620, files.reduce(CGFloat(120)) { $0 + ($1.isPresent && $1.verdict == .verified ? 78 : 104) }))
                    }
            } label: {
                FlowLayout(spacing: 4) {
                    // Problems first, as in Settings › BIOS.
                    if missing > 0 { StatusTag(text: String(localized: "\(missing) missing"), systemImage: "exclamationmark.triangle.fill", tint: .orange) }
                    if unknown > 0 { StatusTag(text: String(localized: "\(unknown) not known"), systemImage: "exclamationmark.circle", tint: .orange) }
                    if verified > 0 { StatusTag(text: String(localized: "\(verified) verified"), systemImage: "checkmark.seal.fill", tint: .green) }
                    if found > 0 { StatusTag(text: String(localized: "\(found) found"), systemImage: "checkmark.circle.fill", tint: .green) }
                    if optional > 0 { StatusTag(text: String(localized: "\(optional) optional"), tint: .secondary) }
                }
            }
        } header: {
            Text("BIOS")
        }
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
            return systemID == .steam ? "Steam" : nil
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
                    Button("Copy Yours") { Self.copy(md5) }
                }
                // The one to look for: what the emulator expects.
                if let expected = check.expected.first?.md5 {
                    Button("Copy Expected MD5") { Self.copy(expected) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
