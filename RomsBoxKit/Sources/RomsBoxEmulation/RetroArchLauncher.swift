import Foundation

/// Launches RetroArch.app's binary directly via `Process`
/// (`Contents/MacOS/RetroArch -L <core.dylib> <rom>`) — never `open -a`,
/// which has a confirmed macOS bug silently dropping passed arguments
/// (libretro/RetroArch#2864) and, since it detaches, wouldn't give a usable
/// PID for termination detection anyway.
public struct RetroArchLauncher: Sendable {
    public let retroArchBinaryURL: URL

    public init(retroArchBinaryURL: URL) {
        self.retroArchBinaryURL = retroArchBinaryURL
    }

    public func launch(coreDylibURL: URL, romURL: URL) throws -> RunningGameSession {
        let process = Process()
        process.executableURL = retroArchBinaryURL
        process.arguments = Self.buildArguments(coreDylibURL: coreDylibURL, romURL: romURL)
        try process.run()
        return RunningGameSession(process: process)
    }

    /// Pure argv construction, split out so it's testable without spawning
    /// a process.
    static func buildArguments(coreDylibURL: URL, romURL: URL) -> [String] {
        ["-L", coreDylibURL.path, romURL.path]
    }
}
