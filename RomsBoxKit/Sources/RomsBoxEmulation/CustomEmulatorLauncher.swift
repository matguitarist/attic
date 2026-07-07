import Foundation

/// Launches a user-defined standalone emulator, LaunchBox-style — same
/// `Process`-based, real-PID, real-`terminationHandler` approach as
/// `RetroArchLauncher`, for the same reliability reasons.
public struct CustomEmulatorLauncher: Sendable {
    public init() {}

    public func launch(
        executableURL: URL,
        argumentTemplate: String,
        romURL: URL,
        workingDirectoryURL: URL? = nil
    ) throws -> RunningGameSession {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ArgumentTemplate.substitute(argumentTemplate, romURL: romURL)
        if let workingDirectoryURL {
            process.currentDirectoryURL = workingDirectoryURL
        }
        try process.run()
        return RunningGameSession(process: process)
    }
}
