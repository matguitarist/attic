import Foundation

/// Launches a user-defined standalone emulator, LaunchBox-style — same
/// real-PID, real-end approach as
/// `RetroArchLauncher`, for the same reliability reasons.
public struct CustomEmulatorLauncher: Sendable {
    public init() {}

    public func launch(
        executableURL: URL,
        argumentTemplate: String,
        romURL: URL,
        workingDirectoryURL: URL? = nil,
        environmentOverrides: [String: String] = [:],
        extraArguments: [String] = [],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) throws -> RunningGameSession {
        // Extra arguments (System Settings' Dolphin overrides) go first,
        // ahead of the template's ROM path.
        let arguments = extraArguments + ArgumentTemplate.substitute(argumentTemplate, romURL: romURL)
        return try RunningGameSession(executableURL, arguments, directory: workingDirectoryURL, environment: environmentOverrides,
                                      onOutput: onOutput)
    }
}
