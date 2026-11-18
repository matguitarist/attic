import Foundation

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

    /// The process that runs a script, from the script's folder.
    public static func scriptProcess(_ script: URL) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = [script.path]
        process.currentDirectoryURL = script.deletingLastPathComponent()
        return process
    }
}
