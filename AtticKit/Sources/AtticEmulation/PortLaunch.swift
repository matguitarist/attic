import Foundation
import ProcessKit

/// How a game in the Ports folder starts: a Mac app is opened, a script
/// (.command or .sh) runs in zsh from its own folder. That is how Batocera's
/// ports folder works, with Mac apps instead of Linux ones.
public enum PortLaunch: Equatable, Sendable {
    case app(URL)
    case script(URL)

    public init?(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "app": self = .app(url)
        case "command", "sh": self = .script(url)
        default: return nil
        }
    }

    /// Runs a script in zsh, from the script's folder, and returns at once.
    public static func startScript(_ script: URL) throws -> Shell.RunningCommand {
        let (arguments, options) = scriptCommand(script)
        return try Shell.start("/bin/zsh", arguments, options: options)
    }

    static func scriptCommand(_ script: URL) -> (arguments: [String], options: Shell.Options) {
        ([script.path], Shell.Options(directory: script.deletingLastPathComponent(), stdout: .discard, stderr: .discard))
    }
}
