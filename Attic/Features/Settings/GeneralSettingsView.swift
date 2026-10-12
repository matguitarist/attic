import SwiftUI
import AtticModels

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
    /// Other front-ends' info files (ES-DE, Batocera) in the ROMs folders.
    @State private var foreignNotes: [URL] = []
    @State private var isConfirmingNotesCleanup = false
    @AppStorage(RemovedSystems.key) private var removedSystems = ""

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
                if !foreignNotes.isEmpty {
                    LabeledContent {
                        Button("Move to Trash…") { isConfirmingNotesCleanup = true }
                    } label: {
                        Text("Other apps' info files")
                        Text("\(foreignNotes.count) systeminfo.txt or _info.txt files from ES-DE or Batocera. Attic writes its own _sysinfo.txt in each system folder.")
                    }
                }
            }
            .task(id: romsRootsStore.rootURLs) { foreignNotes = ROMFolderNotes.foreignFiles(in: romsRootsStore.rootURLs) }
            .confirmationDialog("Move \(foreignNotes.count) info files to the Trash?", isPresented: $isConfirmingNotesCleanup) {
                Button("Move to Trash") {
                    _ = ROMFolderNotes.moveToTrash(foreignNotes)
                    foreignNotes = ROMFolderNotes.foreignFiles(in: romsRootsStore.rootURLs)
                }
            } message: {
                Text("They describe other front-ends, not Attic. Your games and BIOS files aren't touched.")
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
