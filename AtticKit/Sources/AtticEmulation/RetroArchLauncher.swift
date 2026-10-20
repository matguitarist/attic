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

    /// `configURL`/`appendConfigURL` come from `EmulationFolder`, keeping
    /// RetroArch's config, saves and states in the Emulation folder without
    /// touching the user's global retroarch.cfg.
    /// `extraArguments` go before the core and content (`--set-shader` for
    /// System Settings' looks).
    /// With `onOutput`, RetroArch runs `--verbose` and its messages, and the
    /// core's (MAME's "required files are missing"), come back line by line.
    public func launch(
        coreDylibURL: URL, romURL: URL, configURL: URL? = nil, appendConfigURL: URL? = nil, extraArguments: [String] = [],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) throws -> RunningGameSession {
        let process = Process()
        process.executableURL = retroArchBinaryURL
        process.arguments = (onOutput == nil ? [] : ["--verbose"])
            + Self.buildArguments(coreDylibURL: coreDylibURL, romURL: romURL, configURL: configURL, appendConfigURL: appendConfigURL, extraArguments: extraArguments)
        return try RunningGameSession(starting: process, onOutput: onOutput, readsStandardOutput: false)
    }

    /// Pure argv construction, split out so it's testable without spawning
    /// a process.
    static func buildArguments(coreDylibURL: URL, romURL: URL, configURL: URL? = nil, appendConfigURL: URL? = nil, extraArguments: [String] = []) -> [String] {
        var arguments: [String] = []
        if let configURL { arguments += ["--config", configURL.path] }
        if let appendConfigURL { arguments += ["--appendconfig", appendConfigURL.path] }
        return arguments + extraArguments + ["-L", coreDylibURL.path, romURL.path]
    }
}
