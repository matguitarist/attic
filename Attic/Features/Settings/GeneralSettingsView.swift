import SwiftUI

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
    @AppStorage(SidebarStyle.showsLogosKey) private var showsSystemLogos = true
    @State private var language = AppLanguage.current

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
            }

            Section {
                Toggle("Show system logos in the sidebar", isOn: $showsSystemLogos)
            } header: {
                Text("Library")
            } footer: {
                Text("Logos by Dan Patrick. Systems without one show their name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
