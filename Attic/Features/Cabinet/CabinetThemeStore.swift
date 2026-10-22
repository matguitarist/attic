import AppKit
import SwiftUI
import AtticModels

/// Cabinet Mode's themes: the built-in ones, then each folder in
/// Application Support/Attic/Themes holding a `theme.json`, its pictures
/// beside it. A folder named like a built-in theme replaces it.
///
/// Over each theme sit the person's adjustments — layout, art, colors set
/// in Settings or the Start menu — written like a theme file's values and
/// kept per theme, so the theme itself stays as it came.
@Observable @MainActor
final class CabinetThemeStore {
    static let selectedKey = "cabinetTheme"
    static let adjustmentsKey = "cabinetThemeAdjustments"

    struct Installed: Identifiable, Hashable {
        var theme: CabinetTheme
        /// Nil for a built-in theme.
        var folder: URL?
        /// Whether the person's adjustments changed it.
        var isAdjusted = false
        var id: String { theme.id }
        var isBuiltIn: Bool { folder == nil }

        /// A picture the theme names, from its folder.
        func asset(_ name: String?) -> URL? {
            guard let name, let folder else { return nil }
            let url = folder.appending(path: name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// As they came, without adjustments.
    private(set) var themes: [Installed] = []
    var selectedID: String {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: Self.selectedKey)
            refresh()
        }
    }

    /// The selected theme, adjusted.
    private(set) var current = Installed(theme: .showcase)

    /// By theme id.
    private var adjustments: [String: [String: Any]] = [:]

    static var folderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Attic/Themes", directoryHint: .isDirectory)
    }

    static let fileName = "theme.json"

    init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey) ?? CabinetTheme.showcase.id
        if let data = UserDefaults.standard.data(forKey: Self.adjustmentsKey),
           let stored = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            adjustments = stored
        }
        reload()
    }

    // MARK: Adjustments

    /// Sets one of the selected theme's values, named by its path in a
    /// theme file ("palette.accent", "tiles.art"); nil goes back to the
    /// theme's own.
    func adjust(_ path: String, to value: Any?) {
        var object = adjustments[selectedID] ?? [:]
        Self.set(value, at: path.split(separator: ".").map(String.init), in: &object)
        adjustments[selectedID] = object.isEmpty ? nil : object
        saveAdjustments()
    }

    /// Back to the selected theme as it came.
    func resetAdjustments() {
        adjustments[selectedID] = nil
        saveAdjustments()
    }

    private static func set(_ value: Any?, at path: [String], in object: inout [String: Any]) {
        guard let key = path.first else { return }
        if path.count == 1 {
            object[key] = value
        } else {
            var child = object[key] as? [String: Any] ?? [:]
            set(value, at: Array(path.dropFirst()), in: &child)
            object[key] = child.isEmpty ? nil : child
        }
    }

    private func saveAdjustments() {
        if let data = try? JSONSerialization.data(withJSONObject: adjustments) {
            UserDefaults.standard.set(data, forKey: Self.adjustmentsKey)
        }
        refresh()
    }

    private func refresh() {
        var installed = themes.first { $0.id == selectedID } ?? Installed(theme: .showcase)
        if let adjustment = adjustments[installed.id], !adjustment.isEmpty {
            do {
                installed.theme = try installed.theme.applying(adjustment)
                installed.isAdjusted = true
            } catch {
                AppLog.post(.warning, "Ignored adjustments to the \(installed.theme.name) theme: \(Self.describe(error))")
            }
        }
        if installed != current { current = installed }
    }

    /// Reads the Themes folder again, for themes added or edited since.
    func reload() {
        var installed = CabinetTheme.builtIns.map { Installed(theme: $0) }
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.folderURL, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let file = folder.appending(path: Self.fileName)
            guard let data = try? Data(contentsOf: file) else { continue }
            do {
                let theme = try CabinetTheme.decode(data, id: folder.lastPathComponent)
                installed.removeAll { $0.id == theme.id }
                installed.append(Installed(theme: theme, folder: folder))
            } catch {
                AppLog.post(.error, "Couldn't read the theme in \(folder.lastPathComponent): \(Self.describe(error))")
            }
        }
        if installed != themes { themes = installed }
        refresh()
    }

    /// Copies a theme into the Themes folder as a file to edit, selects
    /// the copy and returns its file.
    @discardableResult
    func makeEditableCopy(of source: Installed) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        var name = String(localized: "\(source.theme.name) Copy")
        var number = 2
        while fileManager.fileExists(atPath: Self.folderURL.appending(path: name).path) {
            name = String(localized: "\(source.theme.name) Copy \(number)")
            number += 1
        }
        let folder = Self.folderURL.appending(path: name, directoryHint: .isDirectory)
        if let sourceFolder = source.folder {
            try fileManager.copyItem(at: sourceFolder, to: folder)
        } else {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        var theme = source.theme
        theme.name = name
        theme.author = nil
        let file = folder.appending(path: Self.fileName)
        try theme.encoded().write(to: file)
        writeGuide()
        reload()
        selectedID = folder.lastPathComponent
        return file
    }

    /// What each setting does, beside the themes.
    private func writeGuide() {
        let url = Self.folderURL.appending(path: "Read Me.md")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? Self.guide.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context), DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private static let guide = """
        # Attic Cabinet Mode themes

        Each folder here is a theme: a `theme.json` and any pictures it uses.
        Attic reads them when Cabinet Mode opens; pick one in Settings › General.
        A folder named like a built-in theme (showcase, big-picture, arcade)
        replaces it.

        A theme only needs what differs from its `base` (a built-in theme):

            { "name": "Purple Arcade", "base": "arcade", "palette": { "accent": "#B04CFF" } }

        ## Settings

        - `layout`: `carousel` (a row of covers), `grid` (covers beside a
          details panel) or `wheel` (a wheel of logos beside a screen).
        - `palette`: `background`, `surface` (panels, cards), `accent` (focus),
          `text`, `secondaryText`, `favorite`. Colors are `#RRGGBB` or
          `#RRGGBBAA`.
        - `typography`: `design` (`standard`, `rounded`, `serif`,
          `monospaced`), `fontName` (an installed font family), `titleSize`,
          `bodySize` (points), `uppercase`.
        - `backdrop`: `source` (`none`, `cover`, `screenshot`, `fanart`) for
          the focused game's art behind everything, `blur` (points), `dim`
          (0 to 1), `image` (a picture in the theme's folder, under the art).
        - `tiles`: `art` (`cover`, `screenshot`, `logo`), `size` (of the
          shelf's height; in the wheel, of an entry's), `spacing`,
          `cornerRadius`, `showsBackground`, `focusScale`, `unfocusedOpacity`
          (0 to 1), `focusRing`, `focusGlow`, `showsTitles`.
        - `details`: `media` (`none`, `cover`, `screenshot`, `fanart`),
          `playsVideo`, `showsLogo` (in place of the title), `showsMetadata`,
          `showsDescription`, `descriptionLines`.
        - `header`: `showsLogos` (systems as logos), `showsClock`,
          `showsGameCount`.
        - `menu`: the menu Start opens. `position` (`center`, `leading`,
          `trailing`), `width` (points), `cornerRadius`, `dim` (how much the
          screen behind darkens, 0 to 1).
        - `systems`: the level before the games. `isEnabled` (open on the
          systems, B going back to them), `showsStats`, `artFolder` (a
          folder in the theme with a picture per system, named after its
          ROMs folder: `systems/snes.png`; without one, its covers fan out).
        - `showsHints`: the controller buttons along the bottom.

        """
}

// MARK: - SwiftUI

extension ThemeColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

extension CabinetTheme {
    /// The theme's type at `size` points.
    func font(size: Double, weight: Font.Weight = .regular) -> Font {
        if let fontName = typography.fontName, NSFontManager.shared.availableMembers(ofFontFamily: fontName) != nil {
            return .custom(fontName, size: size).weight(weight)
        }
        let design: Font.Design = switch typography.design {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
        return .system(size: size, weight: weight, design: design)
    }

    var titleFont: Font { font(size: typography.titleSize, weight: .bold) }
    func bodyFont(_ weight: Font.Weight = .regular) -> Font { font(size: typography.bodySize, weight: weight) }
    func largeFont(_ weight: Font.Weight = .semibold) -> Font { font(size: typography.bodySize * 1.3, weight: weight) }
    func smallFont(_ weight: Font.Weight = .regular) -> Font { font(size: typography.bodySize * 0.8, weight: weight) }

    /// Section names and titles, uppercased when the theme says.
    func cased(_ text: String) -> String {
        typography.uppercase ? text.localizedUppercase : text
    }
}

extension CabinetTheme.Layout {
    var title: String {
        switch self {
        case .carousel: String(localized: "Carousel")
        case .grid: String(localized: "Grid")
        case .wheel: String(localized: "Wheel")
        case .list: String(localized: "List")
        }
    }

    var summary: String {
        switch self {
        case .carousel: String(localized: "A row of big covers")
        case .grid: String(localized: "A grid of covers beside the game's details")
        case .wheel: String(localized: "A wheel of logos beside the game's video")
        case .list: String(localized: "A list of titles beside the game's art and details")
        }
    }
}

extension CabinetTheme.Tiles.Art {
    var title: String {
        switch self {
        case .cover: String(localized: "2D Box")
        case .box3D: String(localized: "3D Box")
        case .screenshot: String(localized: "Screenshot")
        case .logo: String(localized: "Logo")
        }
    }
}

extension CabinetTheme {
    /// Accent colors to pick from with a controller.
    static let accentPresets: [(name: String, color: ThemeColor)] = [
        (String(localized: "Pink"), ThemeColor(hex: "#FF2E88")!),
        (String(localized: "Red"), ThemeColor(hex: "#FF453A")!),
        (String(localized: "Orange"), ThemeColor(hex: "#FF9F0A")!),
        (String(localized: "Amber"), ThemeColor(hex: "#E8A33D")!),
        (String(localized: "Yellow"), ThemeColor(hex: "#FFD60A")!),
        (String(localized: "Green"), ThemeColor(hex: "#30D158")!),
        (String(localized: "Teal"), ThemeColor(hex: "#40C8E0")!),
        (String(localized: "Blue"), ThemeColor(hex: "#1A9FFF")!),
        (String(localized: "Indigo"), ThemeColor(hex: "#5E5CE6")!),
        (String(localized: "Purple"), ThemeColor(hex: "#BF5AF2")!),
        (String(localized: "White"), ThemeColor(hex: "#FFFFFF")!)
    ]
}

extension ThemeColor {
    /// The color as a picker gives it, in sRGB.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }
}

extension EnvironmentValues {
    @Entry var cabinetTheme: CabinetThemeStore.Installed = .init(theme: .showcase)
}
