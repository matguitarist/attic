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
        workingDirectoryURL: URL? = nil,
        environmentOverrides: [String: String] = [:],
        extraArguments: [String] = []
    ) throws -> RunningGameSession {
        let process = Process()
        process.executableURL = executableURL
        // Extra arguments (System Settings' Dolphin overrides) go first,
        // ahead of the template's ROM path.
        process.arguments = extraArguments + ArgumentTemplate.substitute(argumentTemplate, romURL: romURL)
        if !environmentOverrides.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environmentOverrides) { _, override in override }
        }
        if let workingDirectoryURL {
            process.currentDirectoryURL = workingDirectoryURL
        }
        try process.run()
        return RunningGameSession(process: process)
    }
}
