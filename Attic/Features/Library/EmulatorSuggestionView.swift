import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// Shown in the inspector when a game's system has no working emulator:
/// offers the catalog's top picks as one-click installs, so the next thing
/// the user does can be pressing Play — not hunting through Settings.
struct EmulatorSuggestionView: View {
    let system: GameSystem
    /// Off inside a Form section, which already draws one.
    var showsBackground = true

    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(EmulatorSetupCoordinator.self) private var setup
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]

    /// Top two keeps the inspector compact; the rest are in Settings.
    private static let maxOptions = 2

    var body: some View {
        let status = setup.status(of: system, retroArchStore: retroArchStore, profiles: profiles)
        if !status.isReady {
            VStack(alignment: .leading, spacing: 10) {
                Label(headline(for: status), systemImage: "gamecontroller")
                    .font(.callout.weight(.semibold))

                ForEach(Array(setup.installOptions(for: system.systemID).prefix(Self.maxOptions).enumerated()), id: \.element) { index, option in
                    optionRow(option, isRecommended: index == 0)
                }

                let missingBIOS = setup.missingBIOS(for: system)
                if !missingBIOS.isEmpty {
                    Label {
                        Text("Also needs BIOS \(missingBIOS.map(\.fileName).joined(separator: ", ")) in \(setup.biosDirectoryPath)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                SettingsLink {
                    Text("More options…")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(showsBackground ? 12 : 0)
            .background(.quaternary.opacity(showsBackground ? 0.5 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func optionRow(_ option: EmulatorSetupCoordinator.InstallOption, isRecommended: Bool) -> some View {
        let isInstalling = setup.isInstalling(option.id)

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isRecommended ? String(localized: "\(option.name) — Recommended") : option.name)
                    .font(.callout)
                Text("\(option.kindLabel). \(option.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isInstalling {
                ProgressView().controlSize(.small)
            } else {
                let button = Button(setup.isInstalled(option, retroArchStore: retroArchStore) ? String(localized: "Use") : String(localized: "Install")) {
                    Task {
                        await setup.install(option, for: [system], makeDefault: true, retroArchStore: retroArchStore, profiles: profiles, modelContext: modelContext)
                    }
                }
                .disabled(setup.isBusy)
                if isRecommended {
                    button.buttonStyle(.borderedProminent)
                } else {
                    button.buttonStyle(.bordered)
                }
            }
        }
    }

    private func headline(for status: EmulatorSetupCoordinator.SystemStatus) -> String {
        switch status {
        case .broken(let reason): reason
        case .notSetUp, .ready: "No emulator set up for \(system.displayName) yet."
        }
    }
}
