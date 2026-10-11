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

    public static var configFileURL: URL {
        applicationSupportURL.appending(path: "config/retroarch.cfg").resolvingSymlinksInPath()
    }

    /// RetroArch's BIOS/"system" directory — where cores look for firmware.
    /// Read from `system_directory` in retroarch.cfg; falls back to
    /// RetroArch's macOS default when unset or set to "default".
    public static func systemDirectoryURL(configContents: String? = try? String(contentsOf: configFileURL, encoding: .utf8)) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fallback = home.appending(path: "Documents/RetroArch/system", directoryHint: .isDirectory)
        guard let value = configContents.flatMap({ configValue(for: "system_directory", in: $0) }),
              !value.isEmpty, value != "default" else {
            return fallback
        }
        if value.hasPrefix("~/") {
            return home.appending(path: String(value.dropFirst(2)), directoryHint: .isDirectory)
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// `key = "value"` lines, RetroArch's config format.
    static func configValue(for key: String, in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return nil
    }
}
