import Foundation

/// Minimal `[Section]` / `Key = Value` editor for emulators' settings files
/// (DuckStation's settings.ini). Only the keys RomsBox sets are touched;
/// every other line — comments, ordering, unknown sections — survives
/// byte-for-byte, since the emulator owns the rest of the file.
public struct IniFile: Sendable, Equatable {
    private var lines: [String]

    public init(contents: String) {
        lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
    }

    public var contents: String { lines.joined(separator: "\n") + "\n" }

    public func value(section: String, key: String) -> String? {
        guard let index = keyLineIndex(section: section, key: key) else { return nil }
        return Self.splitKeyValue(lines[index])?.value
    }

    public mutating func set(section: String, key: String, value: String) {
        let line = "\(key) = \(value)"
        if let index = keyLineIndex(section: section, key: key) {
            lines[index] = line
        } else if let range = sectionRange(section) {
            // Right after the section's last key/value line, so trailing
            // blank lines stay between sections.
            var insertAt = range.upperBound
            while insertAt > range.lowerBound + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            lines.insert(line, at: insertAt)
        } else {
            lines.append("[\(section)]")
            lines.append(line)
        }
    }

    // MARK: - Helpers

    /// Lines from the header up to (not including) the next header.
    private func sectionRange(_ section: String) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { Self.sectionName($0) == section }) else { return nil }
        let end = lines[(header + 1)...].firstIndex { Self.sectionName($0) != nil } ?? lines.count
        return header..<end
    }

    private func keyLineIndex(section: String, key: String) -> Int? {
        guard let range = sectionRange(section) else { return nil }
        return range.dropFirst().first { Self.splitKeyValue(lines[$0])?.key == key }
    }

    private static func sectionName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func splitKeyValue(_ line: String) -> (key: String, value: String)? {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
    }
}
