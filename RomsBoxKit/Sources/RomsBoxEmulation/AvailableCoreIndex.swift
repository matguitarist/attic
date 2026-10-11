import Foundation
import RomsBoxModels

/// A core libretro publishes for this Mac, whether installed or not —
/// what "All Cores" install menus are built from.
public struct AvailableCore: Sendable, Hashable, Identifiable {
    public let coreIdentifier: String
    public let displayName: String
    public let systems: [CanonicalSystemID]

    public var id: String { coreIdentifier }
}

/// Every core described by libretro's `.info` files, narrowed to the ones
/// actually built for Apple Silicon macOS (the info archive also describes
/// cores that only exist for other platforms).
public enum AvailableCoreIndex {
    /// Saved next to the `.info` files by `EmulatorInstaller` — the
    /// buildbot's arm64 core list, one identifier per line.
    public static let availabilityFileName = "available-arm64.txt"

    public static func scan(infoDirectory: URL) -> [AvailableCore] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: infoDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        let available = (try? String(contentsOf: infoDirectory.appending(path: availabilityFileName), encoding: .utf8))
            .map { Set($0.split(whereSeparator: \.isNewline).map(String.init)) }

        return entries
            .filter { $0.pathExtension == "info" }
            .compactMap { infoURL -> AvailableCore? in
                let coreIdentifier = infoURL.deletingPathExtension().lastPathComponent
                // Without the availability list (offline first run), show
                // everything rather than nothing.
                if let available, !available.contains(coreIdentifier) { return nil }
                guard let contents = try? String(contentsOf: infoURL, encoding: .utf8) else { return nil }
                let info = RetroArchCoreInfoParser.parse(contents: contents, coreIdentifier: coreIdentifier, dylibURL: infoURL)
                guard !info.systems.isEmpty else { return nil }
                return AvailableCore(coreIdentifier: coreIdentifier, displayName: info.displayName, systems: info.systems)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Core identifiers linked from the buildbot's directory listing.
    public static func coreIdentifiers(inBuildbotIndex html: String) -> [String] {
        let pattern = /\/([A-Za-z0-9_]+_libretro)\.dylib\.zip"/
        return Array(Set(html.matches(of: pattern).map { String($0.1) })).sorted()
    }
}
