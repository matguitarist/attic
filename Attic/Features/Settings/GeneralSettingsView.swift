import SwiftUI
import SwiftData
import AtticPersistence
import AtticModels
import AtticLibraryScanning
import AtticEmulation

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
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @Environment(ToolsCoordinator.self) private var tools
    @AppStorage(RemovedSystems.key) private var removedSystems = ""
    @AppStorage(LibrarySidebarView.hideEmptySystemsKey) private var hidesEmptySystems = false
    @AppStorage(GameHeaderMedia.previewsKey) private var playsVideoPreviews = true
    @AppStorage(CollectionLogos.folderKey) private var logosFolder = ""
    @AppStorage(ToolsCoordinator.backupFolderKey) private var backupFolder = ""
    @AppStorage(ToolsCoordinator.backsUpWeeklyKey) private var backsUpWeekly = false
    @State private var logosResult: String?
    @Query private var collections: [GameCollection]

    private func chooseLogosFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            logosFolder = url.path
            addLogos()
        }
    }

    private func addLogos() {
        let root = CollectionFolders.root(in: emulationFolderStore.folder.root)
        let added = CollectionLogos.addMissing(to: collections, root: root)
        logosResult = added == 0
            ? String(localized: "No collection without a logo has one in this folder.")
            : String(localized: "\(added) collections got a logo.")
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
                Toggle(isOn: $playsVideoPreviews) {
                    Text("Play video previews")
                    Text("A game's video plays, muted, in the side panel after a moment on it.")
                }
                if let activity = tools.activity {
                    ProgressView(activity.title, value: activity.fraction ?? 0)
                } else if !romsRootsStore.rootURLs.isEmpty {
                    LabeledContent {
                        Button("Analyze…") {
                            Task { await tools.analyzeTidy(romsRoots: romsRootsStore.rootURLs, from: .settings) }
                        }
                        .disabled(tools.isBusy)
                    } label: {
                        Text("Tidy up media and leftovers")
                        Text("Keeps games in ROMs and their media in Media, and moves what other apps left behind to the Trash. You see a report of every change before anything happens.")
                    }
                    LabeledContent {
                        Button("Analyze…") {
                            Task { await tools.analyzeCompression(romsRoots: romsRootsStore.rootURLs, from: .settings) }
                        }
                        .disabled(tools.isBusy)
                    } label: {
                        Text("Compress games")
                        Text("Disc games to CHD, cartridge games to ZIP, without losing anything. You see a report first. Both are also in the Tools menu.")
                    }
                    if tools.isAnalyzing {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .toolsReports(in: .settings)

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
                LabeledContent {
                    HStack {
                        if !logosFolder.isEmpty {
                            Button("Add Logos to Collections") { addLogos() }
                        }
                        Button("Choose…") { chooseLogosFolder() }
                    }
                } label: {
                    Text("Logos folder")
                    Text(logosFolder.isEmpty ? String(localized: "None") : logosFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let logosResult {
                    Text(logosResult).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Collections")
            } footer: {
                Text("A folder of series logos named like ES-DE and Batocera themes' (mario.png, zelda.png…). A collection made from a series, or named like one, takes its logo from here; it's copied into the collection's folder.")
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
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: appearance) { _, newValue in newValue.apply() }
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
                Text("Appearance and Language")
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
                LabeledContent {
                    HStack {
                        Button("Back Up Now") {
                            Task { await tools.backUp(emulationRoot: emulationFolderStore.folder.root, from: .settings) }
                        }
                        .disabled(tools.isBusy)
                        Button("Choose…") {
                            if let folder = tools.chooseBackupFolder() { backupFolder = folder.path }
                        }
                    }
                } label: {
                    Text(backupFolder.isEmpty ? String(localized: "No backup folder") : backupFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let last = ToolsCoordinator.lastBackup {
                        Text("Last backup \(last.formatted(.relative(presentation: .named)))")
                    }
                }
                Toggle("Back up every week", isOn: $backsUpWeekly)
                    .disabled(backupFolder.isEmpty)
            } header: {
                Text("Save Backups")
            } footer: {
                Text("A zip of your saves, save states, collections and gamelists. The newest \(SaveBackup.keptCount) are kept. Another drive or a synced folder keeps them safest.")
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
