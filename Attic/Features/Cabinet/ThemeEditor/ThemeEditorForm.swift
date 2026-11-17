import AppKit
import SwiftUI
import AtticModels

/// Every `CabinetTheme` setting, grouped as in theme.json, each change
/// showing in the preview at once.
struct ThemeEditorForm: View {
    @Binding var theme: CabinetTheme

    var body: some View {
        Form {
            Section("Theme") {
                TextField("Name", text: $theme.name)
                TextField("Author", text: Binding(get: { theme.author ?? "" },
                                                  set: { theme.author = $0.isEmpty ? nil : $0 }))
                picker("Layout", $theme.layout, title: \.title)
                Toggle("Show the controller's buttons", isOn: $theme.showsHints)
            }

            Section("Colors") {
                color("Background", $theme.palette.background)
                color("Panels", $theme.palette.surface)
                color("Accent", $theme.palette.accent)
                color("Text", $theme.palette.text)
                color("Dim Text", $theme.palette.secondaryText)
                color("Favorites", $theme.palette.favorite)
            }

            Section("Type") {
                Picker("Font", selection: $theme.typography.fontName) {
                    Text("The Theme's Design").tag(String?.none)
                    Divider()
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                        Text(verbatim: family).tag(String?.some(family))
                    }
                }
                picker("Design", $theme.typography.design, title: \.title)
                    .disabled(theme.typography.fontName != nil)
                slider("Title Size", $theme.typography.titleSize, 20...96, step: 1, format: .points)
                slider("Text Size", $theme.typography.bodySize, 10...36, step: 1, format: .points)
                Toggle("Capitals", isOn: $theme.typography.uppercase)
            }

            Section("Backdrop") {
                picker("Art", $theme.backdrop.source, title: \.title)
                slider("Blur", $theme.backdrop.blur, 0...60, step: 1, format: .points)
                slider("Darken", $theme.backdrop.dim, 0...1, step: 0.05, format: .percent)
                Toggle(isOn: $theme.backdrop.fade) {
                    Text("Fade into the background")
                    Text("Toward the bottom and the left, so text over it reads with no blur")
                }
                Toggle("Play the game's video there", isOn: $theme.backdrop.playsVideo)
                fileName("Picture", $theme.backdrop.image, help: "A picture in the theme's folder, drawn under the art")
            }

            Section("Game Art") {
                picker("Art", $theme.tiles.art, title: \.title)
                slider("Size", $theme.tiles.size, 0.1...1, step: 0.01, format: .percent)
                slider("Spacing", $theme.tiles.spacing, 0...80, step: 1, format: .points)
                slider("Corner Radius", $theme.tiles.cornerRadius, 0...40, step: 1, format: .points)
                slider("Focused Size", $theme.tiles.focusScale, 1...1.8, step: 0.01, format: .times)
                slider("Others' Opacity", $theme.tiles.unfocusedOpacity, 0...1, step: 0.05, format: .percent)
                Toggle("Card behind the art", isOn: $theme.tiles.showsBackground)
                Toggle("Ring around the focused game", isOn: $theme.tiles.focusRing)
                Toggle("Glow around the focused game", isOn: $theme.tiles.focusGlow)
                Toggle("Titles under the art", isOn: $theme.tiles.showsTitles)
            }

            Section("Details") {
                picker("Picture", $theme.details.media, title: \.title)
                Toggle("Play the game's video there", isOn: $theme.details.playsVideo)
                Toggle("Logo in place of the title", isOn: $theme.details.showsLogo)
                picker("Title Position", $theme.details.titlePosition, title: \.title)
                picker("Details Side", $theme.details.side, title: \.title)
                Toggle("Facts", isOn: $theme.details.showsMetadata)
                Toggle("Description", isOn: $theme.details.showsDescription)
                LabeledContent("Description Lines") {
                    HStack {
                        Text(verbatim: "\(theme.details.descriptionLines)")
                            .monospacedDigit()
                        Stepper("Description Lines", value: $theme.details.descriptionLines, in: 1...12)
                            .labelsHidden()
                    }
                }
                .disabled(!theme.details.showsDescription)
                Toggle("Cartridge or disc on a game's page", isOn: $theme.details.showsPhysicalMedia)
                Toggle("Art beside the list's picture", isOn: $theme.details.showsArt)
            }

            Section("Header") {
                Toggle("System logos", isOn: $theme.header.showsLogos)
                Toggle("Clock", isOn: $theme.header.showsClock)
                Toggle("Number of games", isOn: $theme.header.showsGameCount)
            }

            Section("Systems") {
                Toggle(isOn: $theme.systems.isEnabled) {
                    Text("Open on the systems")
                    Text("B goes back to them from the games")
                }
                picker("Style", $theme.systems.style, title: \.title)
                Toggle("Numbers", isOn: $theme.systems.showsStats)
                Toggle("Picture", isOn: $theme.systems.showsPicture)
                Toggle("Play the system's video", isOn: $theme.systems.playsVideo)
                Toggle("Own band color", isOn: Binding(
                    get: { theme.systems.band != nil },
                    set: { theme.systems.band = $0 ? theme.palette.surface : nil }
                ))
                if let band = theme.systems.band {
                    color("Band", Binding(get: { band }, set: { theme.systems.band = $0 }))
                }
                fileName("Picture Folder", Binding(get: { theme.systems.artFolder },
                                                   set: { theme.systems.artFolder = $0 ?? "" }),
                         help: "A folder in the theme's folder with a picture per system, named after its ROMs folder")
            }

            Section("Menu") {
                picker("Position", $theme.menu.position, title: \.title)
                slider("Width", $theme.menu.width, 280...800, step: 10, format: .points)
                slider("Corner Radius", $theme.menu.cornerRadius, 0...40, step: 1, format: .points)
                slider("Darken Behind", $theme.menu.dim, 0...1, step: 0.05, format: .percent)
            }

            Section("Marquee") {
                picker("Fit", $theme.marquee.fit, title: \.title)
                color("Background", $theme.marquee.background)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Controls

    private func picker<Value: Hashable & CaseIterable>(_ label: LocalizedStringKey, _ value: Binding<Value>,
                                                        title: KeyPath<Value, String>) -> some View
    where Value.AllCases: RandomAccessCollection {
        Picker(label, selection: value) {
            ForEach(Array(Value.allCases), id: \.self) { Text(verbatim: $0[keyPath: title]).tag($0) }
        }
    }

    private func color(_ label: LocalizedStringKey, _ value: Binding<ThemeColor>) -> some View {
        ColorPicker(label, selection: Binding(get: { value.wrappedValue.color }, set: { value.wrappedValue = ThemeColor($0) }))
    }

    enum NumberFormat { case points, percent, times }

    private func slider(_ label: LocalizedStringKey, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double, format: NumberFormat) -> some View {
        LabeledContent(label) {
            HStack {
                // Stepped in the binding: a stepped Slider draws a tick
                // per step.
                Slider(value: Binding(get: { value.wrappedValue },
                                      set: { value.wrappedValue = ($0 / step).rounded() * step }), in: range)
                    .frame(minWidth: 120)
                Text(verbatim: Self.text(value.wrappedValue, format))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    static func text(_ value: Double, _ format: NumberFormat) -> String {
        switch format {
        case .points: value.formatted(.number.precision(.fractionLength(0)))
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .times: "×" + value.formatted(.number.precision(.fractionLength(2)))
        }
    }

    /// A file or folder the theme names, inside its own folder.
    private func fileName(_ label: LocalizedStringKey, _ value: Binding<String?>, help: LocalizedStringKey) -> some View {
        TextField(text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 }),
                  prompt: Text("None")) {
            Text(label)
            Text(help)
        }
    }
}

// MARK: - Names

extension CabinetTheme.Typography.Design {
    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .rounded: String(localized: "Rounded")
        case .serif: String(localized: "Serif")
        case .monospaced: String(localized: "Monospaced")
        }
    }
}

extension CabinetTheme.Backdrop.Source {
    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .cover: String(localized: "2D Box")
        case .screenshot: String(localized: "Screenshot")
        case .fanart: String(localized: "Fan Art")
        }
    }
}

extension CabinetTheme.Details.Media {
    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .cover: String(localized: "2D Box")
        case .box3D: String(localized: "3D Box")
        case .screenshot: String(localized: "Screenshot")
        case .fanart: String(localized: "Fan Art")
        }
    }
}

extension CabinetTheme.Details.TitlePosition {
    var title: String {
        switch self {
        case .top: String(localized: "Under the Picture")
        case .bottom: String(localized: "At the Foot")
        }
    }
}

extension CabinetTheme.Systems.Style {
    var title: String {
        switch self {
        case .showcase: String(localized: "Picture and Cards")
        case .carousel: String(localized: "Logos on a Band")
        }
    }
}

extension CabinetTheme.Menu.Position {
    var title: String {
        switch self {
        case .center: String(localized: "Middle")
        case .leading: String(localized: "Left")
        case .trailing: String(localized: "Right")
        }
    }
}

extension CabinetTheme.Marquee.Fit {
    var title: String {
        switch self {
        case .fit: String(localized: "Whole Marquee")
        case .fill: String(localized: "Fill the Screen")
        }
    }
}
