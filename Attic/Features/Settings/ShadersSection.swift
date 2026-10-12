import SwiftUI
import AtticEmulation

/// Settings › Emulators › Shaders: the retro look by default, and the
/// shader pack it and System Settings' looks come from.
struct ShadersSection: View {
    @Environment(ShaderPackStore.self) private var shaderPack
    @AppStorage(ShaderPackStore.retroLookByDefaultKey) private var retroLookByDefault = false

    var body: some View {
        Section {
            Toggle("Retro look by default", isOn: $retroLookByDefault)

            LabeledContent {
                HStack {
                    if shaderPack.isDownloading || shaderPack.isCheckingForUpdate {
                        ProgressView().controlSize(.small)
                    }
                    switch shaderPack.source {
                    case .missing:
                        Button("Download (54 MB)") { Task { await shaderPack.download() } }
                            .disabled(shaderPack.isDownloading)
                    case .retroArch:
                        Button("Download Attic’s Own") { Task { await shaderPack.download() } }
                            .disabled(shaderPack.isDownloading)
                    case .attic:
                        Button(shaderPack.updateAvailable ? String(localized: "Update") : String(localized: "Download Again")) {
                            Task { await shaderPack.download() }
                        }
                        .disabled(shaderPack.isDownloading)
                    }
                }
            } label: {
                Text("Shader pack")
                Text(sourceDescription)
            }
            if let error = shaderPack.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Shaders")
        } footer: {
            Text("With the retro look, systems left on Default get CRT scanlines (2D consoles and arcade) or an LCD grid (handhelds). Choose a different look per system with right-click › System Settings…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await shaderPack.checkForUpdate() }
    }

    private var sourceDescription: String {
        switch shaderPack.source {
        case .missing:
            String(localized: "Not installed. Looks and the shader library need libretro’s slang shaders.")
        case .retroArch(let url):
            String(localized: "Using RetroArch’s, in \((url.path as NSString).abbreviatingWithTildeInPath). RetroArch’s Online Updater keeps it current.")
        case .attic(let build?):
            shaderPack.updateAvailable
                ? String(localized: "Update available. Installed version built \(build.formatted(date: .abbreviated, time: .omitted)).")
                : String(localized: "Up to date, built \(build.formatted(date: .abbreviated, time: .omitted)).")
        case .attic(nil):
            String(localized: "Installed in the Emulation folder.")
        }
    }
}

/// Every preset in the shader pack, by folder, to pick one for a system.
struct ShaderLibraryView: View {
    let onChoose: (ShaderPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ShaderPackStore.self) private var shaderPack
    @State private var folder: String?
    @State private var selection: ShaderPreset.ID?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(groups, selection: $folder) { group in
                    Text(group.folder.isEmpty ? String(localized: "Other") : group.folder)
                        .badge(group.presets.count)
                        .tag(Optional(group.folder))
                }
                .listStyle(.sidebar)
                .frame(width: 200)

                List(presets, selection: $selection) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                        Text(preset.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(preset.id)
                }
                .contextMenu(forSelectionType: ShaderPreset.ID.self) { _ in } primaryAction: { ids in
                    if let id = ids.first { choose(id) }
                }
                .overlay {
                    if groups.isEmpty {
                        ContentUnavailableView {
                            Label("No Shaders", systemImage: "camera.filters")
                        } description: {
                            Text("Download libretro’s slang shaders to choose from them.")
                        } actions: {
                            if shaderPack.isDownloading {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Download (54 MB)") { Task { await shaderPack.download() } }
                            }
                        }
                    } else if presets.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search Shaders")

            Divider()
            HStack {
                Text("RetroArch’s slang shaders: \(groups.reduce(0) { $0 + $1.presets.count }) presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Shader") { selection.map(choose) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding()
        }
        .frame(width: 680, height: 520)
        .onAppear { folder = folder ?? groups.first { $0.folder == "crt" }?.folder ?? groups.first?.folder }
    }

    private var groups: [ShaderPresetGroup] { shaderPack.presetGroups }

    /// The selected folder's presets, or every match when searching.
    private var presets: [ShaderPreset] {
        if !searchText.isEmpty {
            return groups.flatMap(\.presets).filter { $0.relativePath.localizedCaseInsensitiveContains(searchText) }
        }
        return groups.first { $0.folder == folder }?.presets ?? []
    }

    private func choose(_ id: ShaderPreset.ID) {
        onChoose(ShaderPreset(relativePath: id))
        dismiss()
    }
}
