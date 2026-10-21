import AppKit
import SwiftUI
import AtticModels

/// Cabinet Mode's themes: the built-in ones, then each folder in
/// Application Support/Attic/Themes holding a `theme.json`, its pictures
/// beside it. A folder named like a built-in theme replaces it.
@Observable @MainActor
final class CabinetThemeStore {
    static let selectedKey = "cabinetTheme"

    struct Installed: Identifiable, Hashable {
        var theme: CabinetTheme
        /// Nil for a built-in theme.
        var folder: URL?
        var id: String { theme.id }
        var isBuiltIn: Bool { folder == nil }

        /// A picture the theme names, from its folder.
        func asset(_ name: String?) -> URL? {
            guard let name, let folder else { return nil }
            let url = folder.appending(path: name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private(set) var themes: [Installed] = []
    var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.selectedKey) }
    }

    var current: Installed {
        themes.first { $0.id == selectedID } ?? Installed(theme: .showcase)
    }

    static var folderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Attic/Themes", directoryHint: .isDirectory)
    }

    static let fileName = "theme.json"

    init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey) ?? CabinetTheme.showcase.id
        reload()
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

extension EnvironmentValues {
    @Entry var cabinetTheme: CabinetThemeStore.Installed = .init(theme: .showcase)
}
