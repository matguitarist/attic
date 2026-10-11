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

    init(process: Process) {
        self.process = process
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
