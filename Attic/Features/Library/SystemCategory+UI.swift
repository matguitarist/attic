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

    /// For text Attic writes in English whatever the app's language.
    var englishTitle: String {
        switch self {
        case .console: "Console"
        case .handheld: "Handheld"
        case .arcade: "Arcade"
        case .computer: "Computer"
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
    /// Non-empty categories in display order, each sorted the way the
    /// user chose (by manufacturer unless changed). The one ordering
    /// the sidebar, Cabinet Mode's system bar and LB/RB stepping share, so
    /// moving "next system" always matches what's on screen.
    func groupedByCategory() -> [(category: SystemCategory, systems: [GameSystem])] {
        let byCategory = Dictionary(grouping: self, by: \.category)
        return SystemCategory.allCases.compactMap { category in
            guard let systems = byCategory[category], !systems.isEmpty else { return nil }
            return (category, systems.sorted(by: SystemSortOrder.current.areInIncreasingOrder))
        }
    }

    func orderedByCategory() -> [GameSystem] {
        groupedByCategory().flatMap(\.systems)
    }
}

/// How systems are sorted within each kind (Consoles, Handhelds…) in the
/// sidebar; chosen from the sidebar's toolbar.
enum SystemSortOrder: String, CaseIterable, Identifiable {
    static let key = "systemSortOrder"

    static var current: SystemSortOrder {
        UserDefaults.standard.string(forKey: key).flatMap(SystemSortOrder.init(rawValue:)) ?? .manufacturer
    }

    /// By manufacturer, oldest first within one (NES, SNES, N64…).
    case manufacturer
    case name
    case releaseYear
    case gameCount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manufacturer: String(localized: "Manufacturer")
        case .name: String(localized: "Name")
        case .releaseYear: String(localized: "Release Year")
        case .gameCount: String(localized: "Number of Games")
        }
    }

    func areInIncreasingOrder(_ a: GameSystem, _ b: GameSystem) -> Bool {
        let byName = a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        switch self {
        case .manufacturer: return GameSystem.displayOrder(a, b)
        case .name: return byName
        case .releaseYear:
            let (yearA, yearB) = (a.systemID.releaseYear, b.systemID.releaseYear)
            return yearA != yearB ? yearA < yearB : byName
        case .gameCount:
            return a.gameCount != b.gameCount ? a.gameCount > b.gameCount : byName
        }
    }
}

extension GameSystem {
    static func displayOrder(_ a: GameSystem, _ b: GameSystem) -> Bool {
        let (makerA, makerB) = (a.systemID.maker, b.systemID.maker)
        if makerA != makerB {
            // Emulators of many boards (MAME, FinalBurn Neo) after the makers.
            if (makerA == CanonicalSystemID.multiSystemMaker) != (makerB == CanonicalSystemID.multiSystemMaker) {
                return makerB == CanonicalSystemID.multiSystemMaker
            }
            return makerA.localizedStandardCompare(makerB) == .orderedAscending
        }
        let (yearA, yearB) = (a.systemID.releaseYear, b.systemID.releaseYear)
        if yearA != yearB { return yearA < yearB }
        return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
    }
}

extension CanonicalSystemID {
    static let multiSystemMaker = String(localized: "Multi-System")

    /// The company the sidebar files the system under: the help page's
    /// manufacturer, first one only ("Magnavox, Philips" → Magnavox).
    var maker: String {
        switch self {
        case .mame, .fbneo: return Self.multiSystemMaker
        case .triforce: return "Sega"
        case .threedo: return "3DO"
        default:
            guard let manufacturer = SystemHelpContent.info(for: self)?.manufacturer else { return Self.multiSystemMaker }
            return manufacturer.components(separatedBy: ",")[0]
        }
    }

    var releaseYear: Int { SystemHelpContent.info(for: self)?.year ?? .max }

    /// The system's logo (Attic/Resources/SystemLogos.xcassets), in light
    /// and dark versions; `nil` for systems without one.
    var logo: Image? {
        let name = "SystemLogo/\(baseSystem.rawValue)"
        return NSImage(named: name) == nil ? nil : Image(name)
    }
}
