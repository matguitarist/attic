import SwiftUI
import AtticModels
import AtticLibraryScanning

struct GeneralSettingsView: View {
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(AppUpdater.self) private var appUpdater
    @State private var isChoosingFolder = false
    @State private var isChoosingEmulationFolder = false
    @AppStorage(CabinetView.startInCabinetKey) private var startsInCabinet = false
    @AppStorage(LaunchCoordinator.neoGeoFreePlayKey) private var neoGeoFreePlay = true
    @State private var language = AppLanguage.current
    /// What tidying the ROMs folders would do; nil until worked out.
    @State private var tidyPlan: MediaTidyPlan?
    @State private var isConfirmingTidy = false
    @State private var tidyProgress: Double?
    @AppStorage(RemovedSystems.key) private var removedSystems = ""
    @AppStorage(LibrarySidebarView.hideEmptySystemsKey) private var hidesEmptySystems = false

    private func planTidy() async {
        let roots = romsRootsStore.rootURLs
        tidyPlan = await Task.detached(priority: .utility) { MediaTidier.plan(romsRoots: roots) }.value
    }

    private func tidy(_ plan: MediaTidyPlan) async {
        tidyProgress = 0
        let progress = { @Sendable (value: Double) -> Void in
            Task { @MainActor in tidyProgress = value }
        }
        await Task.detached(priority: .userInitiated) { MediaTidier.apply(plan, progress: progress) }.value
        // Media and gamelists moved: the library picks up their new places.
        await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs)
        tidyProgress = nil
        await planTidy()
    }

    static func tidyDescription(_ plan: MediaTidyPlan) -> String {
        var lines: [String] = []
        if !plan.moves.isEmpty {
            lines.append(String(localized: "\(plan.moves.count) media files in ROM folders move to downloaded_media."))
        }
        let movedGamelists = plan.gamelists.count { $0.from != $0.to }
        if movedGamelists > 0 {
            lines.append(String(localized: "\(movedGamelists) gamelists in ROM folders move to gamelists."))
        }
        let cleanedGamelists = plan.gamelists.count - movedGamelists
        if cleanedGamelists > 0 {
            lines.append(String(localized: "\(cleanedGamelists) gamelists lose old media paths and entries for games that aren't there."))
        }
        if !plan.compress.isEmpty {
            lines.append(String(localized: "\(plan.compress.count) covers are saved as HEIC, which takes less space."))
        }
        if !plan.manuals.isEmpty {
            lines.append(String(localized: "\(plan.manuals.count) heavy manual scans are redrawn lighter, kept only where that saves at least 40%."))
        }
        if !plan.trash.isEmpty {
            let size = ByteCountFormatter.string(fromByteCount: plan.trashBytes, countStyle: .file)
            lines.append(String(localized: "\(size) goes to the Trash: folders Attic doesn't use, media Attic doesn't show (fan art, marquees, 3D boxes…), media for games that aren't there, and other apps' files."))
        }
        lines.append(String(localized: "Your games, saves and BIOS files aren't touched."))
        return lines.joined(separator: "\n\n")
    }

    var body: some View {
        Form {
            Section("ROMs Folders") {
                if romsRootsStore.rootURLs.isEmpty {
                    Text("No folders configured.").foregroundStyle(.secondary)
                } else {
                    ForEach(romsRootsStore.rootURLs, id: \.self) { url in
                        HStack {
                            Text(url.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) { romsRootsStore.removeRoot(url) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add Folder…") { isChoosingFolder = true }
                Toggle("Hide systems with no games", isOn: $hidesEmptySystems)
                if let tidyProgress {
                    ProgressView("Tidying up…", value: tidyProgress)
                } else if let tidyPlan, !tidyPlan.isEmpty {
                    LabeledContent {
                        Button("Tidy Up…") { isConfirmingTidy = true }
                    } label: {
                        Text("Tidy up media and leftovers")
                        Text("Keeps games in ROMs and their media in downloaded_media, and moves what other apps left behind to the Trash.")
                    }
                }
            }
            .task(id: romsRootsStore.rootURLs) { await planTidy() }
            .confirmationDialog("Tidy Up Your ROMs Folders?", isPresented: $isConfirmingTidy, presenting: tidyPlan) { plan in
                Button("Tidy Up") { Task { await tidy(plan) } }
            } message: { plan in
                Text(Self.tidyDescription(plan))
            }

            // Reads `removedSystems` so it redraws when one is added back.
            if !removedSystems.isEmpty {
                Section {
                    ForEach(RemovedSystems.ids, id: \.self) { id in
                        LabeledContent(SystemTaxonomy.definition(for: id)?.displayName ?? id.rawValue) {
                            Button("Add Back") {
                                RemovedSystems.addBack(id)
                                Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
                            }
                        }
                    }
                } header: {
                    Text("Removed Systems")
                } footer: {
                    Text("Removed from the library; their ROM folders are as they were. Adding one back rescans the library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Open Cabinet Mode at launch", isOn: $startsInCabinet)
            } header: {
                Text("Cabinet Mode")
            } footer: {
                Text("Full-screen couch mode (⌘⇧B, or Menu/Start on a controller)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Neo Geo free play", isOn: $neoGeoFreePlay)
            } header: {
                Text("Arcade")
            } footer: {
                Text("Start games without inserting coins. Applies to Neo Geo games run with FinalBurn Neo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $language) {
                    Text("System Default").tag(AppLanguage.systemDefault)
                    ForEach(AppLanguage.available, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: language) { _, newValue in newValue.apply() }

                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("Takes effect when Attic restarts.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.relaunch() }
                    }
                }
            } header: {
                Text("Language")
            }

            Section {
                LabeledContent {
                    HStack {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([emulationFolderStore.folder.root])
                        }
                        Button("Change…") { isChoosingEmulationFolder = true }
                    }
                } label: {
                    Text(emulationFolderStore.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let summary = emulationFolderStore.lastImportSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                if let error = emulationFolderStore.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Emulation Folder")
            } footer: {
                Text("BIOS, saves, save states, RetroArch cores and settings, and emulators installed by Attic all live here — back up or move this one folder to take everything with you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { appUpdater.automaticallyChecksForUpdates },
                    set: { appUpdater.automaticallyChecksForUpdates = $0 }
                ))
                Button("Check Now") { appUpdater.checkForUpdates() }
                    .disabled(!appUpdater.canCheckForUpdates)
            } header: {
                Text("Updates")
            }

            Section {
                HStack {
                    Button("Rescan Library") {
                        Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
                    }
                    .disabled(romsRootsStore.rootURLs.isEmpty || scanCoordinator.state == .scanning)

                    if scanCoordinator.state == .scanning {
                        ProgressView().controlSize(.small)
                    }
                }
                switch scanCoordinator.state {
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                case .idle:
                    if let summary = scanCoordinator.lastScanSummary {
                        Text(summary).foregroundStyle(.secondary)
                    }
                case .scanning:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                romsRootsStore.addRoot(url)
            }
        }
        // A second .fileImporter on the same view is ignored by SwiftUI, so
        // this one hangs off a background view.
        .background {
            Color.clear.fileImporter(isPresented: $isChoosingEmulationFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    emulationFolderStore.setRoot(url)
                    retroArchStore.refresh()
                }
            }
        }
    }
}
