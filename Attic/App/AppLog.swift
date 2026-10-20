import Foundation
import Observation
import os
import Synchronization
import AtticEmulation

/// Attic's log: what it did (launches, quits, failures) and what emulators
/// printed while they ran, shown in Window › Log. Kept in memory for this
/// session and written to ~/Library/Logs/Attic/Attic.log, which survives a
/// crash and can be sent along with a bug report.
@Observable
@MainActor
final class AppLog {
    nonisolated static let shared = AppLog()

    struct Entry: Identifiable, Sendable {
        let id: Int
        let date: Date
        let level: LogLevel
        /// "Attic", or the emulator that printed it: "RetroArch", "Dolphin".
        let source: String
        let message: String
        /// The same line again right after: shown once, "×12".
        var repeats = 1

        var isProblem: Bool { level >= .warning }
    }

    private(set) var entries: [Entry] = []
    private var nextID = 0

    /// Older entries are dropped from the window (the file keeps them).
    private static let limit = 20_000

    nonisolated static let folder = URL.libraryDirectory.appending(path: "Logs/Attic", directoryHint: .isDirectory)
    nonisolated static let fileURL = folder.appending(path: "Attic.log")
    /// The previous log, once Attic.log reaches `maxFileSize`.
    nonisolated static let previousFileURL = folder.appending(path: "Attic.previous.log")
    private nonisolated static let maxFileSize = 5_000_000

    /// The last line each source wrote, so repeats stay out of the file.
    private nonisolated let lastLines = Mutex<[String: String]>([:])

    /// Lines posted from any thread wait here, then reach `entries` in one
    /// batch: RetroArch prints hundreds of lines as a game starts.
    private nonisolated let pending = Mutex<[(Date, LogLevel, String, String)]>([])
    private nonisolated let flushScheduled = Atomic<Bool>(false)
    private nonisolated let file = LogFile(url: AppLog.fileURL, previous: AppLog.previousFileURL, maxSize: AppLog.maxFileSize)
    private nonisolated static let systemLog = Logger(subsystem: "com.attic.app", category: "Log")

    private nonisolated init() {}

    /// Logs from anywhere: Attic's own code or an emulator's output handler.
    nonisolated static func post(_ level: LogLevel, _ message: String, source: String = "Attic") {
        shared.post(level, message, source: source)
    }

    nonisolated private func post(_ level: LogLevel, _ message: String, source: String) {
        let date = Date.now
        let isRepeat = lastLines.withLock { lines in
            defer { lines[source] = message }
            return lines[source] == message
        }
        if !isRepeat { writeOut(date: date, level: level, source: source, message: message) }
        pending.withLock { $0.append((date, level, source, message)) }
        if !flushScheduled.exchange(true, ordering: .acquiringAndReleasing) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                self.flush()
            }
        }
    }

    /// To Attic.log and the system log (Console.app).
    nonisolated private func writeOut(date: Date, level: LogLevel, source: String, message: String) {
        file.append(date: date, level: level, source: source, message: message)
        switch level {
        case .debug: Self.systemLog.debug("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .info: Self.systemLog.info("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .warning: Self.systemLog.warning("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .error: Self.systemLog.error("[\(source, privacy: .public)] \(message, privacy: .public)")
        }
    }

    private func flush() {
        flushScheduled.store(false, ordering: .releasing)
        let batch = pending.withLock { lines in
            defer { lines.removeAll() }
            return lines
        }
        guard !batch.isEmpty else { return }
        for (date, level, source, message) in batch {
            if let last = entries.last, last.source == source, last.level == level, last.message == message {
                entries[entries.count - 1].repeats += 1
                continue
            }
            entries.append(Entry(id: nextID, date: date, level: level, source: source, message: message))
            nextID += 1
        }
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    /// Empties the window; the file keeps everything.
    func clear() {
        entries.removeAll()
    }

    /// Everything shown, as text to paste into a bug report.
    func text(of entries: [Entry]) -> String {
        entries.map {
            LogFile.line(date: $0.date, level: $0.level, source: $0.source, message: $0.message)
                + ($0.repeats > 1 ? " (×\($0.repeats))" : "")
        }
        .joined(separator: "\n")
    }
}

/// Appends lines to Attic.log on its own queue, starting a fresh file
/// (keeping one previous) once it grows past `maxSize`.
private final class LogFile: Sendable {
    private let url: URL
    private let previous: URL
    private let maxSize: Int
    private let queue = DispatchQueue(label: "com.attic.app.log-file", qos: .utility)
    private let handle = Mutex<FileHandle?>(nil)

    init(url: URL, previous: URL, maxSize: Int) {
        self.url = url
        self.previous = previous
        self.maxSize = maxSize
    }

    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds, .withSpaceBetweenDateAndTime]
        formatter.timeZone = .current
        return formatter
    }()

    /// "2026-10-20 14:03:22.123-04:00 ERROR [RetroArch] …"
    static func line(date: Date, level: LogLevel, source: String, message: String) -> String {
        "\(formatter.string(from: date)) \(level.code.padding(toLength: 5, withPad: " ", startingAt: 0)) [\(source)] \(message)"
    }

    func append(date: Date, level: LogLevel, source: String, message: String) {
        let text = Self.line(date: date, level: level, source: source, message: message) + "\n"
        queue.async { [self] in
            handle.withLock { handle in
                if handle == nil { handle = open() }
                guard let file = handle else { return }
                file.write(Data(text.utf8))
                if (try? file.offset()) ?? 0 > UInt64(maxSize) {
                    try? file.close()
                    handle = nil
                    try? FileManager.default.removeItem(at: previous)
                    try? FileManager.default.moveItem(at: url, to: previous)
                }
            }
        }
    }

    private func open() -> FileHandle? {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
        let file = try? FileHandle(forWritingTo: url)
        _ = try? file?.seekToEnd()
        return file
    }
}
