import Foundation
import Observation

/// Persists the user's chosen ROMs root folders across launches. Not
/// sandboxed, so a plain path is sufficient — no security-scoped bookmark
/// bookkeeping needed.
@Observable
@MainActor
final class RomsRootsStore {
    private static let defaultsKey = "romsRootPaths"

    private(set) var rootURLs: [URL]
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let paths = userDefaults.stringArray(forKey: Self.defaultsKey) ?? []
        self.rootURLs = paths.map { URL(fileURLWithPath: $0) }
    }

    func addRoot(_ url: URL) {
        guard !rootURLs.contains(url) else { return }
        rootURLs.append(url)
        persist()
    }

    func removeRoot(_ url: URL) {
        rootURLs.removeAll { $0 == url }
        persist()
    }

    private func persist() {
        userDefaults.set(rootURLs.map(\.path), forKey: Self.defaultsKey)
    }
}
