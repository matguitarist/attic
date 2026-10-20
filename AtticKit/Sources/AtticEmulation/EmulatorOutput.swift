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
            if harmless.contains(where: rest.hasPrefix) { return (.debug, rest) }
            if tag.hasPrefix("[libretro") { return (level, "[Core] " + rest) }
            if tag.hasPrefix("[mvk") { return (level, "[MoltenVK] " + rest) }
            return (level, rest)
        }
        return (freeTextLevel(line), line)
    }

    /// Warnings RetroArch prints on every start that never matter: the MAME
    /// core asks for a newer file interface and works with the older one.
    private static let harmless = ["[Environ] GET_VFS_INTERFACE. Core requested version"]

    private static func freeTextLevel(_ line: String) -> LogLevel {
        let lower = line.lowercased()
        // MAME: a chip no good dump exists of, which still runs.
        if lower.contains("needs redump") || lower.contains("no good dump") { return .warning }
        if lower.firstMatch(of: /\b(error|fatal|failed|failure|cannot|can't|couldn't|unable|missing|not found|wrong|segmentation fault|abort)/) != nil {
            return .error
        }
        if lower.firstMatch(of: /\bwarn(ing)?\b/) != nil { return .warning }
        return .info
    }
}

/// Why a game couldn't start, read from what the emulator printed.
public struct LaunchProblem: Sendable, Equatable {
    /// "MAME 0.289", when the core said.
    public var emulator: String?
    /// Files the set lacks: MAME's "NOT FOUND", FinalBurn Neo's "is required".
    public var missingFiles: [String] = []
    /// Files there but not the ones expected: a bad dump or another version.
    public var wrongFiles: [String] = []
    /// What the emulator said when it gave up.
    public var fatalMessage: String?
}

/// Reads an emulator's lines as a game starts, for `LaunchProblem`.
public final class LaunchDiagnosis: Sendable {
    private let state = Mutex(LaunchProblem())

    public init() {}

    /// Reads one line; true the first time it says the game can't run.
    @discardableResult
    public func read(_ line: String) -> Bool {
        let message = EmulatorOutput.parse(line).message
            .replacing(#/^\[Core\] /#, with: "")
        return state.withLock { problem in
            if problem.emulator == nil, let match = message.wholeMatch(of: /(MAME \d+\.\d+).*/) {
                problem.emulator = String(match.1)
            }
            if let match = message.firstMatch(of: /^(\S+) NOT FOUND/) ?? message.firstMatch(of: /ROM at index \d+ with name (\S+) .*is required/) {
                let file = String(match.1)
                if !problem.missingFiles.contains(file) { problem.missingFiles.append(file) }
            } else if let match = message.firstMatch(of: /^(\S+) WRONG (CHECKSUMS|LENGTH)/) {
                let file = String(match.1)
                if !problem.wrongFiles.contains(file) { problem.wrongFiles.append(file) }
            }
            let isFatal = message.contains("Required files are missing, the machine cannot be run")
                || message.contains("Failed to load content")
            guard isFatal, problem.fatalMessage == nil else { return false }
            problem.fatalMessage = message.replacing(#/^Fatal error: /#, with: "")
            return true
        }
    }

    /// The problem, once the emulator said the game can't run.
    public var problem: LaunchProblem? {
        state.withLock { $0.fatalMessage == nil ? nil : $0 }
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
