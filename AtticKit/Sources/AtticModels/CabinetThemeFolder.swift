import Foundation

/// A theme on disk: a folder in the Themes folder holding `theme.json`
/// (every value, so it reads the same whatever later becomes the default)
/// and any pictures it names. The folder's name is the theme's id.
public enum CabinetThemeFolder {
    public static let fileName = "theme.json"

    /// Writes the theme's file into `folder`, making the folder if needed.
    /// Pictures already there stay.
    public static func save(_ theme: CabinetTheme, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try theme.encoded().write(to: folder.appending(path: fileName), options: .atomic)
    }

    /// The theme in `folder`, its id being the folder's name.
    public static func load(_ folder: URL) throws -> CabinetTheme {
        try CabinetTheme.decode(Data(contentsOf: folder.appending(path: fileName)), id: folder.lastPathComponent)
    }

    /// A folder name for a new theme called `name`: what a file name can't
    /// hold taken out, and a number added when it's taken (by a folder, or
    /// by a built-in theme's id).
    public static func newFolderName(for name: String, taken: Set<String>) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let base = cleaned.isEmpty ? "Theme" : cleaned
        let takenLowercased = Set(taken.map { $0.lowercased() })
        var candidate = base
        var number = 2
        while takenLowercased.contains(candidate.lowercased()) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
    }
}
