import Foundation

/// When a game's file is swapped for another of the same name (a .cue for
/// a .chd, a .sfc for a .zip, or back), what named the old file is pointed
/// at the new one: playlists beside it, and the system's gamelist, so the
/// game keeps its description and the like.
enum ReplacedGameFile {
    static func repoint(in folder: URL, from old: String, to new: String) {
        guard old != new else { return }
        let playlists = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "m3u" }
        for playlist in playlists {
            rewrite(playlist) { text in
                text.components(separatedBy: "\n").map { line in
                    let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name == old || name == "./" + old ? line.replacingOccurrences(of: old, with: new) : line
                }
                .joined(separator: "\n")
            }
        }
        if let gamelist = ImportedMedia.gamelist(near: folder) {
            rewrite(gamelist) {
                $0.replacingOccurrences(of: "<path>./\(escaped(old))</path>", with: "<path>./\(escaped(new))</path>")
            }
        }
    }

    private static func rewrite(_ url: URL, _ change: (String) -> String) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let updated = change(text)
        if updated != text { try? updated.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// As gamelists write a name in element text.
    private static func escaped(_ name: String) -> String {
        name.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
