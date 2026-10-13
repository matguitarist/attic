import Foundation

/// An ES-DE custom collection: `custom-<Name>.cfg`, one game per line,
/// as `%ROMPATH%/snes/Game.sfc` (ES-DE) or a full path such as
/// `/userdata/roms/snes/Game.zip` (Batocera, older EmulationStation).
public struct ESDECustomCollection: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        /// The system's folder in the ROMs folder ("snes").
        public let systemFolder: String
        /// The game's path in it ("Game.sfc", or "Hacks/Game.sfc").
        public let path: String
    }

    public let name: String
    public let entries: [Entry]

    public static func isCollectionFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "cfg" && url.lastPathComponent.lowercased().hasPrefix("custom-")
    }

    public static func read(_ url: URL) -> ESDECustomCollection? {
        guard isCollectionFile(url),
              let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return nil }
        let name = String(url.deletingPathExtension().lastPathComponent.dropFirst("custom-".count))
        return parse(text, name: name)
    }

    static func parse(_ text: String, name: String) -> ESDECustomCollection {
        let entries = text.split(whereSeparator: \.isNewline).compactMap { line -> Entry? in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            var parts = line.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
            if let marker = parts.firstIndex(where: { $0 == "%ROMPATH%" || $0.lowercased() == "roms" }) {
                parts.removeSubrange(...marker)
            } else {
                // No ROMs folder named: the system's folder and the file.
                parts = Array(parts.suffix(2))
            }
            guard parts.count >= 2 else { return nil }
            return Entry(systemFolder: parts[0], path: parts.dropFirst().joined(separator: "/"))
        }
        return ESDECustomCollection(name: name, entries: entries)
    }
}
