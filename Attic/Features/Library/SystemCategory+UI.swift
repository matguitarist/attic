import SwiftUI
import AtticModels
import AtticPersistence

extension SystemCategory {
    var title: String {
        switch self {
        case .console: String(localized: "Consoles")
        case .handheld: String(localized: "Handhelds")
        case .arcade: String(localized: "Arcade")
        case .computer: String(localized: "Computers")
        }
    }

    var symbolName: String {
        switch self {
        case .console: "gamecontroller"
        case .handheld: "iphone.gen1"
        case .arcade: "arcade.stick.console"
        case .computer: "desktopcomputer"
        }
    }
}

extension GameSystem {
    var category: SystemCategory {
        SystemTaxonomy.definition(for: systemID)?.category ?? .console
    }
}

extension Sequence where Element == GameSystem {
    /// Non-empty categories in display order, each sorted by name. The one
    /// ordering the sidebar, Cabinet Mode's system bar and LB/RB stepping share,
    /// so moving "next system" always matches what's on screen.
    func groupedByCategory() -> [(category: SystemCategory, systems: [GameSystem])] {
        let byCategory = Dictionary(grouping: self, by: \.category)
        return SystemCategory.allCases.compactMap { category in
            guard let systems = byCategory[category], !systems.isEmpty else { return nil }
            return (category, systems.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })
        }
    }

    func orderedByCategory() -> [GameSystem] {
        groupedByCategory().flatMap(\.systems)
    }
}

extension CanonicalSystemID {
    /// The system's logo (Attic/Resources/SystemLogos.xcassets), in light
    /// and dark versions; `nil` for systems without one.
    var logo: Image? {
        let name = "SystemLogo/\(rawValue)"
        return NSImage(named: name) == nil ? nil : Image(name)
    }
}

/// Settings › General: show logos instead of names in the sidebar.
enum SidebarStyle {
    static let showsLogosKey = "sidebarShowsSystemLogos"
}
