import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

/// Which system's settings sheet is open; set from the sidebar's
/// context menu.
@Observable
@MainActor
final class SystemSettingsEditor {
    var system: GameSystem?
}

/// Right-click a system › System Settings…: how its games look and play,
/// applied by Attic to the system's emulator at every launch.
struct SystemSettingsView: View {
    let system: GameSystem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @State private var settings = SystemSettings()
    @State private var isDownloadingShaders = false
    @State private var shaderError: String?
    /// Bumped after downloading shaders, so the "missing" note re-checks.
    @State private var shaderCheck = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(system.displayName).font(.title2.bold())
                Group {
                    if let emulatorName {
                        Text("Applies when \(system.displayName) games run in \(emulatorName). “Default” leaves \(emulatorName)’s own setting as it is.")
                    } else {
                        Text(unsupportedMessage)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 8)

            Form {
                if offered.contains(.look) || offered.contains(.integerScaling) {
                    pictureSection
                }
                if !enhancements.isEmpty {
                    enhancementsSection
                }
                if offered.contains(.runAhead) || offered.contains(.rewind) || offered.contains(.resume) {
                    gameplaySection
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Reset to Defaults") { settings = SystemSettings() }
                    .disabled(settings.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 620)
        .onAppear { settings = system.settings }
        .onChange(of: settings) { _, newValue in
            system.settings = newValue
            try? modelContext.save()
        }
    }

    // MARK: - Sections

    private var pictureSection: some View {
        Section {
            if offered.contains(.look) {
                Picker("Look", selection: $settings.look) {
                    Text("Default").tag(SystemSettings.Look?.none)
                    Divider()
                    ForEach(SystemSettingsSupport.looks(for: system.systemID), id: \.self) { look in
                        Text(look.title).tag(Optional(look))
                    }
                }
                if let look = settings.look, look != .none {
                    shaderStatus(for: look)
                }
            }
            if offered.contains(.integerScaling) {
                defaultablePicker("Integer scaling", selection: $settings.integerScaling)
            }
        } header: {
            Text("Picture")
        } footer: {
            Text("Integer scaling sizes the picture by whole multiples, so every pixel is the same size, with black bars around it.")
                .settingsFooter()
        }
    }

    private var enhancements: [SystemSetting] {
        [.internalResolution, .widescreen, .geometryCorrection, .unlimitedSprites, .lcdColors].filter(offered.contains)
    }

    private var enhancementsSection: some View {
        Section {
            if offered.contains(.internalResolution) {
                Picker("Internal resolution", selection: $settings.internalResolution) {
                    Text("Default").tag(Int?.none)
                    Divider()
                    ForEach(SystemSettingsSupport.resolutionChoices(for: backend), id: \.self) { scale in
                        Text(resolutionTitle(scale)).tag(Optional(scale))
                    }
                }
            }
            if offered.contains(.widescreen) {
                defaultablePicker("Widescreen (16:9)", selection: $settings.widescreen)
            }
            if offered.contains(.geometryCorrection) {
                defaultablePicker("Fix wobbly polygons (PGXP)", selection: $settings.geometryCorrection)
            }
            if offered.contains(.unlimitedSprites) {
                defaultablePicker("Remove sprite flicker", selection: $settings.unlimitedSprites)
            }
            if offered.contains(.lcdColors) {
                defaultablePicker("Handheld screen colors", selection: $settings.lcdColors)
            }
        } header: {
            Text("Enhancements")
        } footer: {
            Text(enhancementsFooter)
                .settingsFooter()
        }
    }

    private var gameplaySection: some View {
        Section {
            if offered.contains(.runAhead) {
                Picker("Reduce input lag (run-ahead)", selection: $settings.runAheadFrames) {
                    Text("Default").tag(Int?.none)
                    Divider()
                    Text("Off").tag(Optional(0))
                    Text("1 frame").tag(Optional(1))
                    Text("2 frames").tag(Optional(2))
                }
            }
            if offered.contains(.rewind) {
                defaultablePicker("Rewind", selection: $settings.rewind)
            }
            if offered.contains(.resume) {
                defaultablePicker("Resume where you left off", selection: $settings.resume)
            }
        } header: {
            Text("Gameplay")
        } footer: {
            Text(gameplayFooter)
                .settingsFooter()
        }
    }

    private func defaultablePicker(_ title: LocalizedStringKey, selection: Binding<Bool?>) -> some View {
        Picker(title, selection: selection) {
            Text("Default").tag(Bool?.none)
            Divider()
            Text("On").tag(Optional(true))
            Text("Off").tag(Optional(false))
        }
    }

    // MARK: - Shaders

    @ViewBuilder
    private func shaderStatus(for look: SystemSettings.Look) -> some View {
        let _ = shaderCheck
        if emulationFolderStore.folder.shaderPresetURL(for: look) == nil {
            HStack(alignment: .firstTextBaseline) {
                Label("This look needs RetroArch’s shader pack.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Spacer()
                if isDownloadingShaders {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Download (54 MB)") { downloadShaders() }
                }
            }
            .font(.callout)
            if let shaderError {
                Text(shaderError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func downloadShaders() {
        isDownloadingShaders = true
        shaderError = nil
        let folder = emulationFolderStore.folder
        Task {
            do {
                try await EmulatorInstaller(paths: folder.installerPaths).installShaderPack(into: folder.retroArchShadersDirectory)
            } catch {
                shaderError = error.localizedDescription
            }
            isDownloadingShaders = false
            shaderCheck += 1
        }
    }

    // MARK: - Emulator

    private var backend: SystemSettingsBackend {
        switch system.defaultLaunchTarget {
        case .retroArchCore(let identifier):
            return .retroArch(coreIdentifier: identifier)
        case .emulatorProfile(let id):
            let descriptor = FetchDescriptor<EmulatorProfile>(predicate: #Predicate { $0.id == id })
            return SystemSettingsBackend(catalogEmulatorID: (try? modelContext.fetch(descriptor).first)?.catalogEmulatorID)
        case nil:
            return .other
        }
    }

    private var offered: [SystemSetting] {
        SystemSettingsSupport.settings(for: system.systemID, backend: backend)
    }

    private var emulatorName: String? {
        switch backend {
        case .retroArch(let identifier):
            let core = retroArchStore.core(withIdentifier: identifier)?.displayName
                ?? EmulatorCatalog.recommendation(for: system.systemID)?.cores.first { $0.coreIdentifier == identifier }?.displayName
                ?? identifier
            return String(localized: "RetroArch (\(core))")
        case .duckStation: return EmulatorCatalog.duckStation.name
        case .dolphin: return EmulatorCatalog.dolphin.name
        case .other: return nil
        }
    }

    private var unsupportedMessage: String {
        system.defaultLaunchTarget == nil
            ? String(localized: "Choose an emulator for \(system.displayName) first, in Settings › Emulators.")
            : String(localized: "Attic can’t change this emulator’s settings. Set them up in the emulator itself.")
    }

    private func resolutionTitle(_ scale: Int) -> String {
        scale == 1 ? String(localized: "Native (1×)") : "\(scale)×"
    }

    private var enhancementsFooter: String {
        var lines: [String] = []
        if offered.contains(.internalResolution) {
            lines.append(String(localized: "Higher resolutions are sharper and need a faster Mac."))
        }
        if offered.contains(.widescreen) {
            lines.append(String(localized: "Widescreen shows more of the scene instead of stretching it; some games show glitches at the edges."))
        }
        if offered.contains(.unlimitedSprites) {
            lines.append(String(localized: "Removing sprite flicker draws more sprites per line than the console could."))
        }
        return lines.joined(separator: " ")
    }

    private var gameplayFooter: String {
        var lines: [String] = []
        if offered.contains(.runAhead) {
            lines.append(String(localized: "Run-ahead hides the console’s own input lag; 1 frame suits most games."))
        }
        if offered.contains(.rewind) {
            lines.append(String(localized: "Rewind with the emulator’s rewind hotkey."))
        }
        if offered.contains(.resume) {
            lines.append(String(localized: "Resume saves a state when you quit and loads it the next time."))
        }
        return lines.joined(separator: " ")
    }
}

extension SystemSettings.Look {
    var title: String {
        switch self {
        case .none: String(localized: "Plain pixels")
        case .sharp: String(localized: "Sharp pixels")
        case .crt: String(localized: "CRT TV")
        case .crtCurved: String(localized: "Curved CRT TV")
        case .lcd: String(localized: "Handheld LCD")
        }
    }
}

private extension Text {
    func settingsFooter() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
