import Foundation

/// Substitutes `{romPath}` / `{romDir}` / `{romName}` / `{romNameNoExt}` /
/// `{titleID}` placeholders into a custom emulator's argument template,
/// e.g. `"-batch -f {romPath}"`.
///
/// Splitting happens on the template's own whitespace *before*
/// substitution, so a resolved path containing spaces stays one argv
/// element instead of being split apart.
public enum ArgumentTemplate {
    public static func substitute(_ template: String, romURL: URL) -> [String] {
        let romPath = romURL.path
        let romDir = romURL.deletingLastPathComponent().path
        let romName = romURL.lastPathComponent
        let romNameNoExt = romURL.deletingPathExtension().lastPathComponent
        let titleID = template.contains("{titleID}") ? Self.titleID(romURL: romURL) : ""

        return template
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { token in
                String(token)
                    .replacingOccurrences(of: "{romPath}", with: romPath)
                    .replacingOccurrences(of: "{romDir}", with: romDir)
                    .replacingOccurrences(of: "{romName}", with: romName)
                    .replacingOccurrences(of: "{romNameNoExt}", with: romNameNoExt)
                    .replacingOccurrences(of: "{titleID}", with: titleID)
            }
    }

    /// A PlayStation title ID (`PCSE00000`, four letters then five
    /// digits): the first one in the file, else the last one in its name
    /// (`Persona 4 Golden [PCSE00120].psvita`).
    static func titleID(romURL: URL) -> String {
        let pattern = /[A-Z]{4}[0-9]{5}/
        if let contents = try? String(contentsOf: romURL, encoding: .utf8),
           let match = contents.firstMatch(of: pattern) {
            return String(match.output)
        }
        let name = romURL.deletingPathExtension().lastPathComponent
        return name.matches(of: pattern).last.map { String($0.output) } ?? name
    }
}
