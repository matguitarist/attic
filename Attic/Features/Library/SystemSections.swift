import SwiftUI
import AtticModels
import AtticPersistence

/// What Tools › Verify Games found for a system's games, when it was run
/// and against which DATs, and a button to run it again. Shared by the
/// library's system overview and the system's help page.
struct SystemVerificationSection: View {
    let systemID: CanonicalSystemID
    let games: [Game]
    /// The window the report shows in.
    let host: ToolsCoordinator.Host

    @Environment(ToolsCoordinator.self) private var tools
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore

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
                if let activity = tools.activity, tools.reportHost == host {
                    ProgressView(value: activity.fraction ?? 0)
                        .frame(maxWidth: 120)
                }
            }
        } header: {
            Text("Verification")
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
    let games: [Game]
    @State private var bytes: Int64?

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
