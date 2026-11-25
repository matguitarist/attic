import Foundation
import ProcessKit

/// A launched emulator, through ProcessKit's `Shell.start`: a real PID,
/// its end, and a stop. Launchers spawn the binary directly (never
/// `open -a`), since `open` detaches and silently drops arguments on
/// macOS (see RetroArchLauncher).
public final class RunningGameSession: Sendable {
    private let command: Shell.RunningCommand

    /// The program and its arguments, for Attic's log.
    public let commandLine: [String]

    /// Starts `executableURL`. With `onOutput`, what it prints comes back
    /// line by line, on a background thread: standard error, and standard
    /// output unless `readsStandardOutput` is false (RetroArch prints its
    /// messages to both). Without, its output is dropped.
    init(
        _ executableURL: URL, _ arguments: [String], directory: URL? = nil, environment: [String: String] = [:],
        onOutput: (@Sendable (String) -> Void)?, readsStandardOutput: Bool = true
    ) throws {
        commandLine = [executableURL.path] + arguments
        var options = Shell.Options(directory: directory, environment: environment, stdout: .discard, stderr: .discard)
        var tool = executableURL.path
        var toolArguments = arguments
        if let onOutput {
            options.stdout = .capture
            options.stderr = .merged
            // A game runs for hours: only the end of what it printed stays.
            options.keepsLast = Self.keptOutput
            // Only \n ends a line; the line's indent stays for `EmulatorOutput`.
            options.lineBreaks = .newline
            options.onLine = { line in
                if let line = Self.trimmed(line) { onOutput(line) }
            }
            if !readsStandardOutput {
                // Standard error alone: zsh swaps it onto the pipe and drops
                // standard output, then becomes the emulator (same PID).
                toolArguments = ["-c", #"exec "$0" "$@" 2>&1 >/dev/null"#, tool] + arguments
                tool = "/bin/zsh"
            }
        }
        command = try Shell.start(tool, toolArguments, options: options)
    }

    /// The most output kept in memory while a game runs; every line still
    /// reaches `onOutput`.
    static let keptOutput = 64 << 10

    /// What it printed, the last `keptOutput` bytes, once it has ended.
    var output: Shell.Output? { command.output }

    /// The line without its trailing spaces; nil when nothing is left.
    static func trimmed(_ line: String) -> String? {
        var line = line
        while line.last?.isWhitespace == true { line.removeLast() }
        return line.isEmpty ? nil : line
    }

    public var isRunning: Bool { command.isRunning }
    public var processIdentifier: pid_t { command.pid }

    /// Its exit status once it has ended (128 + the signal when one ended it).
    public func waitUntilExit() async -> Int32 {
        await command.wait().status
    }

    /// Stops it and whatever it started.
    public func terminate() {
        command.stop()
    }
}
