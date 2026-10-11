import SwiftUI

struct GeneralSettingsView: View {
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @State private var isChoosingFolder = false
    @State private var isChoosingEmulationFolder = false

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
                Text("BIOS, saves, save states, RetroArch cores and settings, and emulators installed by RomsBox all live here — back up or move this one folder to take everything with you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(20)
        .frame(width: 520)
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
