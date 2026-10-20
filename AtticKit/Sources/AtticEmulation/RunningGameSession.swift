import Foundation

/// Thin wrapper around a launched `Process`, exposing an async termination
/// signal. Launchers spawn the binary directly (never `open -a`) so this
/// gets a real PID and a reliable `terminationHandler` — `open` detaches
/// and silently drops arguments on macOS (see RetroArchLauncher).
///
/// `Process` isn't `Sendable`, but all access here is funneled through
/// `terminationHandler`/`isRunning`/`terminate()`, which are documented
/// thread-safe on `Process`, so this is a safe `@unchecked Sendable`.
public final class RunningGameSession: @unchecked Sendable {
    private let process: Process

    /// The program and its arguments, for Attic's log.
    public var commandLine: [String] {
        [process.executableURL?.path ?? ""] + (process.arguments ?? [])
    }

    /// Starts `process`. With `onOutput`, what it prints comes back line by
    /// line, on a background thread: standard error, and standard output
    /// unless `readsStandardOutput` is false (RetroArch prints its messages
    /// to both). Without, it goes wherever Attic's own output goes.
    init(starting process: Process, onOutput: (@Sendable (String) -> Void)?, readsStandardOutput: Bool = true) throws {
        self.process = process
        if let onOutput {
            let error = Pipe()
            process.standardError = error
            LineSplitter(onLine: onOutput).attach(to: error)
            if readsStandardOutput {
                // Its own splitter, so the two never mix mid-line.
                let output = Pipe()
                process.standardOutput = output
                LineSplitter(onLine: onOutput).attach(to: output)
            } else {
                process.standardOutput = FileHandle.nullDevice
            }
        }
        try process.run()
    }

    public var isRunning: Bool { process.isRunning }
    public var processIdentifier: pid_t { process.processIdentifier }

    public func waitUntilExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            if !process.isRunning {
                continuation.resume(returning: process.terminationStatus)
                return
            }
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }
    }

    public func terminate() {
        process.terminate()
    }
}
