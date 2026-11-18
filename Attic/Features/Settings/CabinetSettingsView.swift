import AppKit
import SwiftUI
import AtticModels

/// Settings › Cabinet Mode: opening it, its theme, and the person's
/// adjustments to the theme (layout, art, colors), kept apart from it.
struct CabinetSettingsView: View {
    @Environment(CabinetThemeStore.self) private var cabinetThemes
    @AppStorage(CabinetView.startInCabinetKey) private var startsInCabinet = false
    @AppStorage(GameHeaderMedia.previewsKey) private var playsVideoPreviews = true
    @AppStorage("videoPreviewsMuted") private var videoPreviewsMuted = true
    @AppStorage(CabinetSystemsView.playsVideosKey) private var playsSystemVideos = false
    @AppStorage(CabinetMarqueeDisplay.key) private var marqueeDisplayName = ""
    @AppStorage(CabinetAttractView.minutesKey) private var attractMinutes = CabinetAttractView.defaultMinutes
    @AppStorage(CabinetMusic.enabledKey) private var playsMusic = false
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @State private var screensRevision = 0
    @State private var themeError: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var cabinetThemes = cabinetThemes
        let theme = cabinetThemes.current.theme

        Form {
            Section {
                Toggle("Open Cabinet Mode at launch", isOn: $startsInCabinet)
                Toggle("Play video sound", isOn: Binding(get: { !videoPreviewsMuted }, set: { videoPreviewsMuted = !$0 }))
                    .disabled(!playsVideoPreviews)
                Toggle(isOn: $playsSystemVideos) {
                    Text("Play system and collection videos")
                    Text("On the systems, after a moment, in place of the picture")
                }
                Picker(selection: $attractMinutes) {
                    ForEach(CabinetAttractView.minuteChoices, id: \.self) { minutes in
                        if minutes == 0 { Text("Never").tag(0) } else { Text("After \(minutes) minutes").tag(minutes) }
                    }
                } label: {
                    Text("Attract Mode")
                    Text("With nothing pressed for a while, random games play their video or show their art. A plays the game on screen.")
                }
                LabeledContent {
                    HStack {
                        Button("Show Music Folder") { showMusicFolder() }
                        Toggle("Play Music", isOn: $playsMusic).labelsHidden()
                    }
                } label: {
                    Text("Play Music")
                    Text("Shuffles the tracks in the Music folder of the Emulation folder, or in Music/snes and such while that system's games are shown. MP3, AAC, WAV, AIFF or FLAC.")
                }
                Picker(selection: $marqueeDisplayName) {
                    let _ = screensRevision
                    ForEach(CabinetMarqueeDisplay.options, id: \.self) { Text(verbatim: CabinetMarqueeDisplay.title(of: $0)).tag($0) }
                } label: {
                    Text("Marquee Display")
                    Text("For a cabinet with a second screen: the selected game's marquee, else its logo, and the system's logo on the systems")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    screensRevision += 1
                }
            } footer: {
                Text("Full-screen couch mode: ⌘⇧B, or Menu/Start on a controller. Start opens its menu, where all of this can be set from the couch too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    HStack {
                        Picker("Theme", selection: $cabinetThemes.selectedID) {
                            ForEach(cabinetThemes.themes) { installed in
                                Text(verbatim: installed.theme.name).tag(installed.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Edit…") { openWindow(id: ThemeEditorView.windowID) }
                            .help("Change every setting of this theme with a live preview, and save it as a theme")
                        Button("Customize…") { customizeTheme() }
                            .help("Copy this theme into the Themes folder as a file to edit")
                        Button("Show Themes Folder") { showThemesFolder() }
                    }
                } label: {
                    Text("Theme")
                    Text(themeSummary(cabinetThemes.current))
                }
                if let themeError {
                    Text(themeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("A theme is a theme.json file in the Themes folder. Customize makes one from the selected theme with your changes below, and Cabinet Mode reads the folder again each time it opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Layout", selection: Binding(
                    get: { theme.layout },
                    set: { cabinetThemes.adjust("layout", to: $0.rawValue) }
                )) {
                    ForEach(CabinetTheme.Layout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Game Art", selection: Binding(
                    get: { theme.tiles.art },
                    set: { cabinetThemes.adjust("tiles.art", to: $0.rawValue) }
                )) {
                    ForEach(CabinetTheme.Tiles.Art.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(selection: Binding(
                    get: { theme.details.side },
                    set: { cabinetThemes.adjust("details.side", to: $0.rawValue) }
                )) {
                    ForEach(CabinetTheme.Details.Side.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Details Side")
                    Text("The grid's details panel, and the art and facts on a game's page")
                }
                LabeledContent("Colors") {
                    // Names and wells in their own columns, so the wells
                    // line up whatever the names' lengths.
                    Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            colorCell("Accent", \.accent, key: "accent")
                            colorCell("Background", \.background, key: "background")
                            colorCell("Panels", \.surface, key: "surface")
                        }
                        GridRow {
                            colorCell("Text", \.text, key: "text")
                            colorCell("Dim Text", \.secondaryText, key: "secondaryText")
                            colorCell("Favorites", \.favorite, key: "favorite")
                        }
                    }
                    .fixedSize()
                }
                Toggle(isOn: Binding(
                    get: { theme.details.showsPhysicalMedia },
                    set: { cabinetThemes.adjust("details.showsPhysicalMedia", to: $0) }
                )) {
                    Text("Show the cartridge or disc")
                    Text("At the corner of the box on a game's page")
                }
                Toggle("Open on the systems", isOn: Binding(
                    get: { theme.systems.isEnabled },
                    set: { cabinetThemes.adjust("systems.isEnabled", to: $0) }
                ))
                Toggle("Show the controller's buttons", isOn: Binding(
                    get: { theme.showsHints },
                    set: { cabinetThemes.adjust("showsHints", to: $0) }
                ))
            } header: {
                HStack {
                    Text("Look")
                    Spacer()
                    if cabinetThemes.current.isAdjusted {
                        Button("Back to the Theme's Own") { cabinetThemes.resetAdjustments() }
                            .buttonStyle(.link)
                    }
                }
            } footer: {
                Text("These change \(theme.name) for you, kept apart from the theme itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { cabinetThemes.reload() }
    }

    private func themeSummary(_ installed: CabinetThemeStore.Installed) -> String {
        let layout = installed.theme.layout.summary
        return installed.isBuiltIn ? layout : String(localized: "\(layout), from the Themes folder")
    }

    /// A color's name, right-aligned in its column, then its well.
    @ViewBuilder
    private func colorCell(_ name: LocalizedStringKey, _ keyPath: WritableKeyPath<CabinetTheme.Palette, ThemeColor>, key: String) -> some View {
        Text(name)
            .gridColumnAlignment(.trailing)
            .padding(.leading, 12)
        ColorPicker(name, selection: colorBinding(keyPath, key: key))
            .labelsHidden()
            .gridColumnAlignment(.leading)
    }

    /// One of the theme's colors, adjusted when picked.
    private func colorBinding(_ keyPath: WritableKeyPath<CabinetTheme.Palette, ThemeColor>, key: String) -> Binding<Color> {
        Binding(
            get: { cabinetThemes.current.theme.palette[keyPath: keyPath].color },
            set: { cabinetThemes.adjust("palette.\(key)", to: ThemeColor($0).hex) }
        )
    }

    private func customizeTheme() {
        do {
            let file = try cabinetThemes.makeEditableCopy(of: cabinetThemes.current)
            themeError = nil
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            themeError = error.localizedDescription
        }
    }

    private func showThemesFolder() {
        try? FileManager.default.createDirectory(at: CabinetThemeStore.folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(CabinetThemeStore.folderURL)
    }
}

private extension CabinetSettingsView {
    /// Makes the Music folder if needed and shows it in the Finder.
    func showMusicFolder() {
        let folder = emulationFolderStore.folder.root.appending(path: CabinetMusic.folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
