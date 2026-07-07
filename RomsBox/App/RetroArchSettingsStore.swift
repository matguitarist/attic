import Foundation
import Observation
import RomsBoxModels
import RomsBoxEmulation

/// Detected RetroArch install + core index, refreshed on demand (manual
/// "Refresh Cores" button — no filesystem watching for MVP).
@Observable
@MainActor
final class RetroArchSettingsStore {
    private static let installPathKey = "retroArchInstallPath"
    private let userDefaults: UserDefaults

    var installURL: URL {
        didSet { userDefaults.set(installURL.path, forKey: Self.installPathKey) }
    }

    private(set) var cores: [RetroArchCoreInfo] = []
    private(set) var isInstalled = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let savedPath = userDefaults.string(forKey: Self.installPathKey)
        self.installURL = savedPath.map { URL(fileURLWithPath: $0) } ?? RetroArchInstallation.defaultAppURL
        refresh()
    }

    func refresh() {
        isInstalled = RetroArchInstallation.isInstalled(appURL: installURL)
        cores = RetroArchCoreIndex.scan(
            coresDirectory: RetroArchInstallation.coresDirectoryURL,
            infoDirectory: RetroArchInstallation.infoDirectoryURL
        )
    }

    func cores(for canonicalID: CanonicalSystemID) -> [RetroArchCoreInfo] {
        cores.filter { $0.canonicalSystemID == canonicalID }
    }

    func core(withIdentifier identifier: String) -> RetroArchCoreInfo? {
        cores.first { $0.coreIdentifier == identifier }
    }

    var binaryURL: URL { RetroArchInstallation.binaryURL(appURL: installURL) }
}
