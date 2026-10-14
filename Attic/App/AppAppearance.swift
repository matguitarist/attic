import AppKit

/// Light or dark for Attic's windows, or as macOS is set. Cabinet Mode
/// stays dark either way.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "appearance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "Same as macOS")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: key).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// Sets every window's appearance, the open ones included.
    @MainActor func apply() {
        NSApplication.shared.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
