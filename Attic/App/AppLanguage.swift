import AppKit
import Foundation

/// Attic's display language: either the system's, or one picked in
/// Settings. Stored the standard macOS way — an `AppleLanguages` override
/// in the app's own defaults, the same setting System Settings › Language
/// & Region › Applications writes — so it's honored by the frameworks too
/// (date formats, system-provided menu items), and needs a relaunch.
///
/// The list offers whatever translations the app bundle actually ships, so
/// adding a language to Localizable.xcstrings makes it appear here with no
/// code change.
enum AppLanguage: Hashable {
    case systemDefault
    case specific(String)

    private static let defaultsKey = "AppleLanguages"

    static var available: [AppLanguage] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted()
            .map(AppLanguage.specific)
    }

    /// The override in Attic's own defaults domain — not
    /// `UserDefaults.standard.array(forKey:)`, which also returns the
    /// system-wide language list and would make "System Default"
    /// impossible to tell apart.
    static var current: AppLanguage {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: bundleID)?[defaultsKey] as? [String],
              let first = languages.first else {
            return .systemDefault
        }
        return .specific(first)
    }

    /// What this process is actually running with.
    static let atLaunch = current

    var displayName: String {
        guard case .specific(let code) = self else { return String(localized: "System Default") }
        // Each language named in itself ("Français", "Deutsch"), as macOS does.
        return Locale(identifier: code).localizedString(forIdentifier: code)?.localizedCapitalized ?? code
    }

    func apply() {
        switch self {
        case .systemDefault:
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        case .specific(let code):
            UserDefaults.standard.set([code], forKey: Self.defaultsKey)
        }
    }

    @MainActor static func relaunch() {
        let appPath = Bundle.main.bundlePath
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Waits for this process to exit before reopening, or `open` would
        // just re-focus the instance that's quitting.
        relauncher.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"", appPath]
        try? relauncher.run()
        NSApp.terminate(nil)
    }
}
