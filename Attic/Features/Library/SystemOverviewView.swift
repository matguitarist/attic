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
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
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
                        FlowLayout(spacing: 4) {
                            ForEach(extensions, id: \.self) { ext in
                                Text(verbatim: ".\(ext)")
                                    .monospaced()
                                    .font(.caption)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: .rect(cornerRadius: 4))
                            }
                        }
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
            ForEach(biosRequirements, id: \.fileName) { requirement in
                let present = requirement.isPresent(in: emulationFolderStore.folder.bios)
                LabeledContent {
                    Label(present ? "Found" : "Missing",
                          systemImage: present ? "checkmark.circle.fill" : (requirement.required ? "exclamationmark.triangle.fill" : "circle"))
                        .foregroundStyle(present ? .green : (requirement.required ? .orange : .secondary))
                } label: {
                    Text(requirement.fileName)
                        .monospaced()
                        .textSelection(.enabled)
                    Text([requirement.required ? String(localized: "Required") : String(localized: "Optional"), requirement.note]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    if let dumps = SystemFacts.supportedDumps(requirement) {
                        Text(dumps)
                    }
                }
            }
            Button("Show BIOS Folder") {
                let folder = emulationFolderStore.folder.bios
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
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
