import Foundation

/// Sets values in a TOML settings file the way an emulator writes it
/// (xemu's `xemu.toml`): `[table.subtable]` headers, then `key = value`
/// lines. Everything else in the file is kept as it is.
public struct TOMLSettings: Sendable, Equatable {
    public private(set) var lines: [String]

    public init(contents: String) {
        lines = contents.isEmpty ? [] : contents.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
    }

    public var contents: String { lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n" }

    /// The raw value text of `key` in `table`, or nil.
    public func value(table: String, key: String) -> String? {
        guard let index = keyIndex(table: table, key: key) else { return nil }
        return lines[index].split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Sets `key` to a string (written as a literal string, so paths need
    /// no escaping).
    public mutating func set(table: String, key: String, string: String) {
        set(table: table, key: key, raw: "'" + string.replacingOccurrences(of: "'", with: "") + "'")
    }

    public mutating func set(table: String, key: String, bool: Bool) {
        set(table: table, key: key, raw: bool ? "true" : "false")
    }

    mutating func set(table: String, key: String, raw: String) {
        let line = "\(key) = \(raw)"
        if let index = keyIndex(table: table, key: key) {
            lines[index] = line
        } else if let header = lines.firstIndex(where: { Self.tableName($0) == table }) {
            // After the table's last key, before the next table.
            var end = header + 1
            while end < lines.count, Self.tableName(lines[end]) == nil { end += 1 }
            while end > header + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            lines.insert(line, at: end)
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
            lines += ["[\(table)]", line]
        }
    }

    private func keyIndex(table: String, key: String) -> Int? {
        var current = ""
        for (index, line) in lines.enumerated() {
            if let name = Self.tableName(line) {
                current = name
            } else if current == table,
                      line.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == key {
                return index
            }
        }
        return nil
    }

    private static func tableName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), !trimmed.hasPrefix("[["), let end = trimmed.firstIndex(of: "]") else { return nil }
        return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
    }
}
