import Foundation

/// Substitutes `{romPath}` / `{romDir}` / `{romName}` / `{romNameNoExt}`
/// placeholders into a custom emulator's argument template, e.g.
/// `"-batch -f {romPath}"`.
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

        return template
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { token in
                String(token)
                    .replacingOccurrences(of: "{romPath}", with: romPath)
                    .replacingOccurrences(of: "{romDir}", with: romDir)
                    .replacingOccurrences(of: "{romName}", with: romName)
                    .replacingOccurrences(of: "{romNameNoExt}", with: romNameNoExt)
            }
    }
}
