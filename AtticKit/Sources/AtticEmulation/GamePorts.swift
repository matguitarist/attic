import Foundation
import AtticModels

/// Engine ports whose library entry isn't the file their core reads, the
/// way Batocera and RetroBat lay them out:
///
/// - DOOM 3: `Doom 3.boom3` holds the path of the game's first pak
///   (`base\pak000.pk4`); Resurrection of Evil (`d3xp\…`) runs in its own
///   core.
/// - Flashback: `Flashback.rem` stands for the folder of the same name
///   beside it; REminiscence is given the first level's file in it.
public enum GamePorts {
    /// The file the core is given for `romURL`.
    public static func contentFile(for romURL: URL, system: CanonicalSystemID) -> URL {
        switch system {
        case .doom3:
            return doom3Pak(for: romURL) ?? romURL
        case .reminiscence:
            let folder = romURL.deletingPathExtension()
            let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            return files.first { $0.lastPathComponent.lowercased() == "level1.map" }
                ?? files.first { ["map", "lev", "aba"].contains($0.pathExtension.lowercased()) }
                ?? romURL
        default:
            return romURL
        }
    }

    /// The core that runs `romURL`, when it isn't the system's: DOOM 3's
    /// expansion needs boom3_xp.
    public static func coreIdentifier(for romURL: URL, system: CanonicalSystemID) -> String? {
        guard system == .doom3, let pak = doom3Pak(for: romURL) else { return nil }
        return pak.deletingLastPathComponent().lastPathComponent.lowercased() == "d3xp" ? "boom3_xp_libretro" : nil
    }

    /// The pak a `.boom3` file names, relative to it, written with either
    /// slash.
    static func doom3Pak(for romURL: URL) -> URL? {
        guard let text = try? String(contentsOf: romURL, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty })
        else { return nil }
        let path = line.replacingOccurrences(of: "\\", with: "/")
        return romURL.deletingLastPathComponent().appending(path: path)
    }
}
