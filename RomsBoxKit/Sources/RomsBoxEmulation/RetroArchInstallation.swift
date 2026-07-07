import Foundation

/// Locates the installed RetroArch.app and its supporting directories.
/// Cores/info/config live under Application Support regardless of where the
/// .app bundle itself is installed — only the launch binary path depends on
/// the app location.
public enum RetroArchInstallation {
    public static let defaultAppURL = URL(fileURLWithPath: "/Applications/RetroArch.app")

    public static func binaryURL(appURL: URL = defaultAppURL) -> URL {
        appURL.appending(path: "Contents/MacOS/RetroArch")
    }

    public static func isInstalled(appURL: URL = defaultAppURL) -> Bool {
        FileManager.default.fileExists(atPath: binaryURL(appURL: appURL).path)
    }

    private static var applicationSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/RetroArch")
    }

    /// `~/Library/Application Support/RetroArch/cores` is a symlink into a
    /// sandboxed container on at least some installs (confirmed: the Mac App
    /// Store build of RetroArch links it to
    /// `~/Library/Containers/com.libretro.dist.RetroArch/Data/...`).
    /// `FileManager.contentsOfDirectory(at:)` fails with ENOTDIR ("Not a
    /// directory") on the unresolved symlink path even though the directory
    /// itself is perfectly readable — resolve symlinks first.
    public static var coresDirectoryURL: URL {
        applicationSupportURL.appending(path: "cores").resolvingSymlinksInPath()
    }

    public static var infoDirectoryURL: URL {
        applicationSupportURL.appending(path: "info").resolvingSymlinksInPath()
    }
}
