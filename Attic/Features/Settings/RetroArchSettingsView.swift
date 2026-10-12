import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

/// Settings › Emulators: RetroArch itself, one-click setup for every
/// system in the library, and per-system defaults with install options.
struct RetroArchSettingsView: View {
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(EmulatorSetupCoordinator.self) private var setup
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]
    @State private var isChoosingApp = false

    var body: some View {
        Form {
            retroArchSection
            ShadersSection()

            if !retroArchStore.cores.isEmpty {
                installedCoresSection
            }

            if !systems.isEmpty {
                setUpAllSection

                Section {
                    ForEach(systems) { system in
                        SystemEmulatorRow(system: system, profiles: profiles)
                    }
                } header: {
                    Text("Systems")
                } footer: {
                    Text("Downloads come straight from each project's official source — libretro's buildbot for RetroArch and its cores, GitHub releases for standalone emulators. BIOS files are never included: dump them from hardware you own and put them in \(setup.biosDirectoryPath).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CustomEmulatorsSection()
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result {
                retroArchStore.installURL = url
                retroArchStore.refresh()
            }
        }
        .alert("Install Failed", isPresented: Binding(get: { setup.lastError != nil }, set: { if !$0 { setup.dismissError() } })) {
            Button("OK") { setup.dismissError() }
        } message: {
            Text(setup.lastError ?? "")
        }
    }

    private var retroArchSection: some View {
        Section("RetroArch") {
            LabeledContent {
                HStack {
                    if setup.isInstalling(EmulatorSetupCoordinator.retroArchKey) {
                        ProgressView().controlSize(.small)
                    } else if !retroArchStore.isInstalled {
                        Button("Install RetroArch") {
                            Task { await setup.installRetroArch(retroArchStore: retroArchStore) }
                        }
                    }
                    Menu {
                        Button("Choose RetroArch.app…") { isChoosingApp = true }
                        Button("Refresh Cores") { retroArchStore.refresh() }
                        if retroArchStore.isInstalled {
                            Button("Reinstall Latest Version") {
                                Task { await setup.installRetroArch(retroArchStore: retroArchStore) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        retroArchStatusText,
                        systemImage: retroArchStore.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(retroArchStore.isInstalled ? .green : .orange)
                    Text("\(retroArchStore.installURL.path) · \(retroArchStore.cores.count) cores")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var setUpAllSection: some View {
        let needing = setup.systemsNeedingSetup(systems, retroArchStore: retroArchStore, profiles: profiles)
        Section {
            LabeledContent {
                Button(setup.isBusy ? String(localized: "Installing…") : String(localized: "Set Up All Systems")) {
                    Task {
                        await setup.setUpAllSystems(systems, retroArchStore: retroArchStore, profiles: profiles, modelContext: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(needing.isEmpty || setup.isBusy)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(needing.isEmpty ? String(localized: "Every system has an emulator") : String(localized: "\(needing.count) of \(systems.count) systems need an emulator"))
                    Text(needing.isEmpty ? String(localized: "Change any system's choice below.") : String(localized: "Installs the recommended emulator for each, and RetroArch if needed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let label = setup.activeInstalls.values.sorted().first {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(label).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var installedCoresSection: some View {
        let updatable = setup.coresWithUpdates(retroArchStore: retroArchStore)

        return Section {
            ForEach(retroArchStore.cores) { core in
                InstalledCoreRow(core: core)
            }
        } header: {
            HStack {
                Text("Installed Cores")
                Spacer()
                if setup.isCheckingForCoreUpdates {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check for Updates") {
                        Task { await setup.checkForCoreUpdates(retroArchStore: retroArchStore) }
                    }
                    .buttonStyle(.link)
                }
                if !updatable.isEmpty {
                    Button("Update All (\(updatable.count))") {
                        Task { await setup.updateAllCores(retroArchStore: retroArchStore) }
                    }
                    .disabled(setup.isBusy)
                }
            }
        } footer: {
            if let lastCheck = setup.lastCoreUpdateCheck {
                Text("Last checked \(lastCheck.formatted(.relative(presentation: .named))). Updates come from the same nightly builds RetroArch's Online Updater uses, compared by checksum — a core only shows an update when its code actually changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var retroArchStatusText: String {
        guard retroArchStore.isInstalled else { return String(localized: "Not installed") }
        if let retroArchVersion { return String(localized: "Installed — \(retroArchVersion)") }
        return String(localized: "Installed")
    }

    private var retroArchVersion: String? {
        Bundle(url: retroArchStore.installURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

/// One system: its status, BIOS warnings, default-emulator picker, and
/// an Install menu of the catalog's options (best first).
private struct SystemEmulatorRow: View {
    let system: GameSystem
    let profiles: [EmulatorProfile]

    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(EmulatorSetupCoordinator.self) private var setup
    @Environment(\.modelContext) private var modelContext
    @Environment(HelpNavigator.self) private var helpNavigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let status = setup.status(of: system, retroArchStore: retroArchStore, profiles: profiles)
        let missingBIOS = setup.missingBIOS(for: system)

        LabeledContent {
            HStack(spacing: 8) {
                defaultPicker
                installMenu
                Button {
                    helpNavigator.open(.system(system.systemID), with: openWindow)
                } label: {
                    Label("About This System", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Emulators, BIOS and tips for \(system.displayName)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(system.displayName)
                statusLine(status)
                if !missingBIOS.isEmpty {
                    Label("Needs BIOS: \(missingBIOS.map(\.fileName).joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Put these in \(setup.biosDirectoryPath)")
                }
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ status: EmulatorSetupCoordinator.SystemStatus) -> some View {
        switch status {
        case .ready(let name):
            Label(name, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .broken(let reason):
            Label(reason, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
        case .notSetUp:
            Label("No emulator", systemImage: "circle.dashed").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var defaultPicker: some View {
        Picker("Default", selection: targetBinding) {
            Text("None").tag(Optional<LaunchTargetReference>.none)

            let matchingCores = retroArchStore.cores(for: system.systemID)
            if !matchingCores.isEmpty {
                Section("RetroArch Cores") {
                    ForEach(matchingCores) { core in
                        Text(core.displayName)
                            .tag(Optional(LaunchTargetReference.retroArchCore(coreIdentifier: core.coreIdentifier)))
                    }
                }
            }

            let matchingProfiles = profiles.filter { $0.assignedSystemIDs.contains(system.systemID) || $0.assignedSystemIDs.contains(system.systemID.baseSystem) }
            if !matchingProfiles.isEmpty {
                Section("Standalone Emulators") {
                    ForEach(matchingProfiles) { profile in
                        Text(profile.name)
                            .tag(Optional(LaunchTargetReference.emulatorProfile(id: profile.id)))
                    }
                }
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var installMenu: some View {
        let options = setup.installOptions(for: system.systemID)
        let others = setup.otherCoreOptions(for: system.systemID, retroArchStore: retroArchStore)
        let installingHere = (options + others).contains { setup.isInstalling($0.id) }

        return Menu {
            Section("Recommended") {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    installButton(option, title: menuTitle(for: option, isRecommended: index == 0), subtitle: "\(option.kindLabel) — \(option.summary)")
                }
            }
            if !others.isEmpty {
                Menu("More Cores (\(others.count))") {
                    ForEach(others) { option in
                        installButton(option, title: menuTitle(for: option, isRecommended: false), subtitle: nil)
                    }
                }
            }
        } label: {
            if installingHere {
                ProgressView().controlSize(.small)
            } else {
                Label("Install", systemImage: "arrow.down.circle")
            }
        }
        .fixedSize()
        .disabled(options.isEmpty || installingHere)
    }

    private func installButton(_ option: EmulatorSetupCoordinator.InstallOption, title: String, subtitle: String?) -> some View {
        Button {
            Task {
                await setup.install(option, for: [system], makeDefault: true, retroArchStore: retroArchStore, profiles: profiles, modelContext: modelContext)
            }
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }

    private func menuTitle(for option: EmulatorSetupCoordinator.InstallOption, isRecommended: Bool) -> String {
        var title = isRecommended ? String(localized: "\(option.name) (Recommended)") : option.name
        if setup.isInstalled(option, retroArchStore: retroArchStore) { title += " ✓" }
        return title
    }

    private var targetBinding: Binding<LaunchTargetReference?> {
        Binding(
            get: { system.defaultLaunchTarget },
            set: { newValue in
                system.defaultLaunchTarget = newValue
                try? system.modelContext?.save()
            }
        )
    }
}

/// One installed core: what it runs, where it lives, and whether a newer
/// build exists.
private struct InstalledCoreRow: View {
    let core: RetroArchCoreInfo

    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(EmulatorSetupCoordinator.self) private var setup

    var body: some View {
        LabeledContent {
            status
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(core.displayName)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if setup.isInstalling(EmulatorSetupCoordinator.key(forCore: core.coreIdentifier)) {
            ProgressView().controlSize(.small)
        } else {
            switch setup.coreUpdateStatuses[core.coreIdentifier] {
            case .updateAvailable:
                Button("Update") {
                    Task { await setup.updateCore(core, retroArchStore: retroArchStore) }
                }
                .disabled(setup.isBusy)
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notOnBuildbot:
                Text("Not on buildbot")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("libretro doesn't publish this core for Apple Silicon, so there's nothing to compare it with.")
            case nil:
                EmptyView()
            }
        }
    }

    private var detailLine: String {
        let systems = core.systems
            .compactMap { SystemTaxonomy.definition(for: $0)?.displayName }
            .joined(separator: ", ")
        let inRetroArchFolder = !core.dylibURL.path.hasPrefix(retroArchStore.emulationFolderStore.folder.cores.path)
        return [systems.isEmpty ? nil : systems, inRetroArchFolder ? String(localized: "in RetroArch's folder") : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
