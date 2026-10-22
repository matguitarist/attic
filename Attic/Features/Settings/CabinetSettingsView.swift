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
    @State private var themeError: String?

    var body: some View {
        @Bindable var cabinetThemes = cabinetThemes
        let theme = cabinetThemes.current.theme

        Form {
            Section {
                Toggle("Open Cabinet Mode at launch", isOn: $startsInCabinet)
                Toggle("Play video sound", isOn: Binding(get: { !videoPreviewsMuted }, set: { videoPreviewsMuted = !$0 }))
                    .disabled(!playsVideoPreviews)
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
