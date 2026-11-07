import Foundation
import LogKit
import os
import Synchronization
import AtticEmulation

/// Attic's log: what it did (launches, quits, failures) and what emulators
/// printed while they ran, shown in Window › Log by LogKit's viewer. Written
/// to ~/Library/Logs/Attic/Attic.log in Attic's own line format, which
/// survives a crash and can be sent along with a bug report; the viewer keeps
/// this session's newest lines in memory.
enum AppLog {
    /// What the viewer shows: memory only, the newest 20,000 lines. The file keeps everything.
    nonisolated static let store = LogStore(fileURL: nil, limit: 20_000)

    nonisolated static let folder = URL.libraryDirectory.appending(path: "Logs/Attic", directoryHint: .isDirectory)
    nonisolated static let fileURL = folder.appending(path: "Attic.log")
    /// The previous log, once Attic.log reaches `maxFileSize`.
    nonisolated static let previousFileURL = folder.appending(path: "Attic.previous.log")
    private nonisolated static let maxFileSize = 5_000_000

    /// The last line each source wrote, so repeats stay out of the file.
    private nonisolated static let lastLines = Mutex<[String: String]>([:])
    private nonisolated static let file = LogFile(url: fileURL, previous: previousFileURL, maxSize: maxFileSize)
    private nonisolated static let systemLog = Logger(subsystem: "com.attic.app", category: "Log")

    /// Logs from anywhere: Attic's own code or an emulator's output handler.
    nonisolated static func post(_ level: AtticEmulation.LogLevel, _ message: String, source: String = "Attic") {
        let isRepeat = lastLines.withLock { lines in
            defer { lines[source] = message }
            return lines[source] == message
        }
        if !isRepeat { writeOut(date: .now, level: level, source: source, message: message) }
        store.post(level.logKitLevel, message, source: source)
    }

    /// To Attic.log and the system log (Console.app).
    nonisolated private static func writeOut(date: Date, level: AtticEmulation.LogLevel, source: String, message: String) {
        file.append(date: date, level: level, source: source, message: message)
        switch level {
        case .debug: systemLog.debug("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .info: systemLog.info("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .warning: systemLog.warning("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .error: systemLog.error("[\(source, privacy: .public)] \(message, privacy: .public)")
        }
    }
}

extension AtticEmulation.LogLevel {
    /// The same level in LogKit, for the viewer.
    nonisolated var logKitLevel: LogKit.LogLevel {
        switch self {
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
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
    static func line(date: Date, level: AtticEmulation.LogLevel, source: String, message: String) -> String {
        "\(formatter.string(from: date)) \(level.code.padding(toLength: 5, withPad: " ", startingAt: 0)) [\(source)] \(message)"
    }

    func append(date: Date, level: AtticEmulation.LogLevel, source: String, message: String) {
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
