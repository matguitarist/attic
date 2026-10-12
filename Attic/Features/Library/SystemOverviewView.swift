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
                        Text("\(system.gameCount) games")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                LabeledContent("Emulator", value: emulatorName ?? String(localized: "None chosen"))
                Button("System Settings…") { systemSettingsEditor.system = system }
                ScrapeSelectionButton(title: "Scrape This System", selection: .system(system.systemID))
                Button("About This System") {
                    helpNavigator.open(.system(system.systemID), with: openWindow)
                }
            }

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
    }

    // MARK: - BIOS

    /// What the system's recommended emulator needs. Attic only checks for
    /// these; they're dumped from hardware the user owns.
    private var biosRequirements: [BIOSRequirement] {
        EmulatorCatalog.recommendation(for: system.systemID)?.bios ?? []
    }

    private var biosSection: some View {
        Section {
            ForEach(biosRequirements, id: \.fileName) { requirement in
                let present = FileManager.default.fileExists(atPath: emulationFolderStore.folder.bios.appending(path: requirement.fileName).path)
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
