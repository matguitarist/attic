import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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
    @Environment(ShaderPackStore.self) private var shaderPack
    @AppStorage(ShaderPackStore.retroLookByDefaultKey) private var retroLookByDefault = false
    @State private var settings = SystemSettings()
    @State private var isBrowsingShaders = false
    @State private var isChoosingShaderFile = false
    /// What each setting is on Default, read from the emulator.
    @State private var emulatorDefaults = SystemSettings()

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
        .sheet(isPresented: $isBrowsingShaders) {
            ShaderLibraryView { preset in
                settings.shaderPreset = preset.relativePath
                settings.look = nil
            }
        }
        .fileImporter(isPresented: $isChoosingShaderFile, allowedContentTypes: [.shaderPreset]) { result in
            if case .success(let url) = result {
                settings.shaderPreset = url.path
                settings.look = nil
            }
        }
        .onAppear {
            settings = system.settings
            emulatorDefaults = emulationFolderStore.folder.currentDefaults(for: backend)
        }
        .onChange(of: settings) { _, newValue in
            system.settings = newValue
            try? modelContext.save()
        }
    }

    // MARK: - Sections

    private var pictureSection: some View {
        Section {
            if offered.contains(.look) {
                Picker("Look", selection: lookChoice) {
                    Text(defaultLookTitle).tag(LookChoice.automatic)
                    Divider()
                    ForEach(SystemSettingsSupport.looks(for: system.systemID), id: \.self) { look in
                        Text(look.title).tag(LookChoice.look(look))
                    }
                    if let preset = settings.shaderPreset {
                        Divider()
                        Text(ShaderLibrary.displayName(forPreset: preset)).tag(LookChoice.preset(preset))
                    }
                    Divider()
                    Text("Shader Library…").tag(LookChoice.browse)
                    Text("Choose File…").tag(LookChoice.chooseFile)
                }
                shaderStatus
            }
            if offered.contains(.integerScaling) {
                defaultablePicker("Integer scaling", selection: $settings.integerScaling, default: emulatorDefaults.integerScaling)
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
                    Text(defaultTitle(emulatorDefaults.internalResolution.map(resolutionTitle))).tag(Int?.none)
                    Divider()
                    ForEach(SystemSettingsSupport.resolutionChoices(for: backend), id: \.self) { scale in
                        Text(resolutionTitle(scale)).tag(Optional(scale))
                    }
                }
            }
            if offered.contains(.widescreen) {
                defaultablePicker("Widescreen (16:9)", selection: $settings.widescreen, default: emulatorDefaults.widescreen)
            }
            if offered.contains(.geometryCorrection) {
                defaultablePicker("Fix wobbly polygons (PGXP)", selection: $settings.geometryCorrection, default: emulatorDefaults.geometryCorrection)
            }
            if offered.contains(.unlimitedSprites) {
                defaultablePicker("Remove sprite flicker", selection: $settings.unlimitedSprites, default: emulatorDefaults.unlimitedSprites)
            }
            if offered.contains(.lcdColors) {
                defaultablePicker("Handheld screen colors", selection: $settings.lcdColors, default: emulatorDefaults.lcdColors)
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
                    Text(defaultTitle(emulatorDefaults.runAheadFrames.map(runAheadTitle))).tag(Int?.none)
                    Divider()
                    ForEach([0, 1, 2], id: \.self) { frames in
                        Text(runAheadTitle(frames)).tag(Optional(frames))
                    }
                }
            }
            if offered.contains(.rewind) {
                defaultablePicker("Rewind", selection: $settings.rewind, default: emulatorDefaults.rewind)
            }
            if offered.contains(.resume) {
                defaultablePicker("Resume where you left off", selection: $settings.resume, default: emulatorDefaults.resume)
            }
        } header: {
            Text("Gameplay")
        } footer: {
            Text(gameplayFooter)
                .settingsFooter()
        }
    }

    private func defaultablePicker(_ title: LocalizedStringKey, selection: Binding<Bool?>, default defaultValue: Bool?) -> some View {
        Picker(title, selection: selection) {
            Text(defaultTitle(defaultValue.map { $0 ? String(localized: "On") : String(localized: "Off") })).tag(Bool?.none)
            Divider()
            Text("On").tag(Optional(true))
            Text("Off").tag(Optional(false))
        }
    }

    // MARK: - Shaders

    /// The Look menu's entries: the built-in looks, a preset from the
    /// shader library or a file, and the two items that pick one.
    private enum LookChoice: Hashable {
        case automatic
        case look(SystemSettings.Look)
        case preset(String)
        case browse
        case chooseFile
    }

    private var lookChoice: Binding<LookChoice> {
        Binding {
            if let preset = settings.shaderPreset { return .preset(preset) }
            return settings.look.map(LookChoice.look) ?? .automatic
        } set: { choice in
            switch choice {
            case .automatic: settings.look = nil; settings.shaderPreset = nil
            case .look(let look): settings.look = look; settings.shaderPreset = nil
            case .preset: break
            case .browse: isBrowsingShaders = true
            case .chooseFile: isChoosingShaderFile = true
            }
        }
    }

    /// "Default", naming the retro look when that's what Default means.
    private var defaultLookTitle: String {
        defaultTitle(retroLookByDefault ? SystemSettingsSupport.defaultLook(for: system.systemID)?.title : nil)
    }

    /// "Default (On)": what the emulator does when Attic leaves it alone.
    private func defaultTitle(_ value: String?) -> String {
        value.map { String(localized: "Default (\($0))") } ?? String(localized: "Default")
    }

    private func runAheadTitle(_ frames: Int) -> String {
        switch frames {
        case 0: String(localized: "Off")
        case 1: String(localized: "1 frame")
        default: String(localized: "\(frames) frames")
        }
    }

    /// Says when the chosen look can't be shown, and offers the download.
    @ViewBuilder
    private var shaderStatus: some View {
        let _ = shaderPack.revision
        let chosen = settings.shaderPreset != nil || (settings.look.map { $0 != .none } ?? false)
        if chosen, emulationFolderStore.folder.retroArchShaderArguments(for: settings).isEmpty {
            if let preset = settings.shaderPreset, preset.hasPrefix("/") {
                Label("Can’t find this shader file.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Label("This look needs RetroArch’s shader pack.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if shaderPack.isDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Download (54 MB)") { Task { await shaderPack.download() } }
                    }
                }
                .font(.callout)
                if let error = shaderPack.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
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
        case .none: String(localized: "None")
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

extension UTType {
    /// A RetroArch slang shader preset.
    static let shaderPreset = UTType(filenameExtension: "slangp") ?? .data
}
