import Foundation
import Synchronization

/// How serious a line in Attic's log is.
public enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case debug, info, warning, error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The level's code in the log file: "ERROR".
    public var code: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        }
    }
}

/// Reads what an emulator prints while it runs. RetroArch run with
/// `--verbose` tags each line ("[INFO] [Content]: …", "[libretro ERROR] …",
/// the latter from the core: MAME, FinalBurn Neo); other emulators print
/// free text, judged by its words.
public enum EmulatorOutput {
    public static func parse(_ line: String) -> (level: LogLevel, message: String) {
        // Indented lines continue a listing (MoltenVK's 126 Vulkan extensions).
        if line.first?.isWhitespace == true {
            return (.debug, line.trimmingCharacters(in: .whitespaces))
        }
        let tags: [(String, LogLevel)] = [
            ("[libretro ERROR]", .error), ("[libretro WARN]", .warning),
            ("[libretro INFO]", .info), ("[libretro DEBUG]", .debug),
            ("[ERROR]", .error), ("[WARN]", .warning), ("[INFO]", .info), ("[DEBUG]", .debug),
            // MoltenVK, under RetroArch's Vulkan driver: its warnings are
            // Metal features it does without, a dozen per game start.
            ("[mvk-error]", .error), ("[mvk-warn]", .debug), ("[mvk-info]", .debug)
        ]
        for (tag, level) in tags where line.hasPrefix(tag) {
            // The core's lines and MoltenVK's say whose they are.
            let rest = line.dropFirst(tag.count).trimmingCharacters(in: .whitespaces)
            if tag.hasPrefix("[libretro") { return (level, "[Core] " + rest) }
            if tag.hasPrefix("[mvk") { return (level, "[MoltenVK] " + rest) }
            return (level, rest)
        }
        return (freeTextLevel(line), line)
    }

    private static func freeTextLevel(_ line: String) -> LogLevel {
        let lower = line.lowercased()
        if lower.firstMatch(of: /\b(error|fatal|failed|failure|cannot|can't|couldn't|unable|missing|not found|segmentation fault|abort)/) != nil {
            return .error
        }
        if lower.firstMatch(of: /\bwarn(ing)?\b/) != nil { return .warning }
        return .info
    }
}

/// Cuts a pipe's output into lines as it arrives, for `RunningGameSession`.
final class LineSplitter: Sendable {
    private let pending = Mutex(Data())
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    /// Reads `pipe` until the process closes it.
    func attach(to pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                finish()
            } else {
                feed(data)
            }
        }
    }

    func feed(_ data: Data) {
        let lines = pending.withLock { buffer -> [Data] in
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[(newline + 1)...])
            }
            return lines
        }
        lines.forEach(emit)
    }

    func finish() {
        let rest = pending.withLock { buffer in
            defer { buffer = Data() }
            return buffer
        }
        if !rest.isEmpty { emit(rest) }
    }

    /// Keeps the line's indent, which `EmulatorOutput` reads.
    private func emit(_ data: Data) {
        var line = String(decoding: data, as: UTF8.self)
        while line.last?.isWhitespace == true { line.removeLast() }
        if !line.isEmpty { onLine(line) }
    }
}
