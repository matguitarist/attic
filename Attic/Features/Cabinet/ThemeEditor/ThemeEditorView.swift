import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// The Theme Editor window: a Cabinet theme's every setting beside a live
/// preview with the library's games. A theme from the Themes folder saves
/// over its theme.json; a built-in one saves as a new theme folder.
struct ThemeEditorView: View {
    static let windowID = "theme-editor"

    @Environment(CabinetThemeStore.self) private var themeStore
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @Query(sort: \GameCollection.name) private var collections: [GameCollection]

    /// The theme being edited, as it was opened or last saved.
    @State private var source: CabinetThemeStore.Installed?
    @State private var draft: CabinetTheme = .showcase
    @State private var page = ThemePreviewPage.games
    @State private var sections: [CabinetSection] = []
    @State private var selection: LibrarySelection = .favorites
    @State private var pendingThemeID: String?
    @State private var error: String?

    private var hasChanges: Bool { source.map { $0.theme != draft } ?? false }

    var body: some View {
        HStack(spacing: 0) {
            ThemeEditorForm(theme: $draft)
                .frame(width: 400)
            Divider()
            VStack(spacing: 0) {
                ThemePreview(installed: previewInstalled, page: page, sections: sections, selection: $selection)
                    .padding(20)
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding(.bottom, 12)
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }
        .toolbar { toolbar }
        .navigationTitle(source == nil ? String(localized: "Theme Editor") : draft.name)
        .navigationSubtitle(subtitle)
        .onAppear {
            themeStore.reload()
            if source == nil { open(themeStore.current) }
            sections = CabinetSection.build(collections: collections, systems: systems, emulationRoot: emulationFolderStore.folder.root)
            // A system rather than Favorites, which may be empty.
            selection = sections.first { if case .system = $0.selection { true } else { false } }?.selection
                ?? sections.first?.selection ?? .favorites
        }
        .confirmationDialog("Discard your changes to \(draft.name)?", isPresented: Binding(
            get: { pendingThemeID != nil }, set: { if !$0 { pendingThemeID = nil } }
        )) {
            Button("Discard Changes", role: .destructive) {
                if let id = pendingThemeID, let installed = themeStore.themes.first(where: { $0.id == id }) { open(installed) }
                pendingThemeID = nil
            }
        }
    }

    /// The draft drawn as if installed, so pictures it names come from
    /// its folder.
    private var previewInstalled: CabinetThemeStore.Installed {
        CabinetThemeStore.Installed(theme: draft, folder: source?.folder)
    }

    private var subtitle: String {
        guard let source else { return "" }
        if source.isBuiltIn { return String(localized: "Built in: saving makes a new theme") }
        return hasChanges ? String(localized: "Edited") : String(localized: "In the Themes folder")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Theme", selection: Binding(
                get: { source?.id ?? "" },
                set: { id in
                    guard id != source?.id else { return }
                    if hasChanges {
                        pendingThemeID = id
                    } else if let installed = themeStore.themes.first(where: { $0.id == id }) {
                        open(installed)
                    }
                }
            )) {
                ForEach(themeStore.themes) { Text(verbatim: $0.theme.name).tag($0.id) }
            }
            .help("The theme to edit")
        }
        ToolbarItem(placement: .principal) {
            Picker("Preview", selection: $page) {
                ForEach(ThemePreviewPage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("What the preview shows")
        }
        ToolbarItem {
            Picker("Section", selection: $selection) {
                ForEach(sections) { Text(verbatim: $0.title).tag($0.selection) }
            }
            .help("Whose games the preview shows")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Revert") { draft = source?.theme ?? draft }
                .disabled(!hasChanges)
                .help("Back to the theme as last saved")
            Button("Save as New Theme") { saveAsNew() }
                .help("Save these settings as a new theme in the Themes folder")
            if source?.isBuiltIn == false {
                Button("Save") { save() }
                    .keyboardShortcut("s")
                    .disabled(!hasChanges)
                    .help("Save over this theme's theme.json")
            }
        }
    }

    private func open(_ installed: CabinetThemeStore.Installed) {
        source = installed
        draft = installed.theme
        error = nil
    }

    private func save() {
        guard let source, !source.isBuiltIn else { return saveAsNew() }
        do {
            try themeStore.save(draft, over: source)
            open(themeStore.themes.first { $0.id == source.id } ?? source)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveAsNew() {
        guard let source else { return }
        do {
            open(try themeStore.saveAsNew(draft, from: source))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
