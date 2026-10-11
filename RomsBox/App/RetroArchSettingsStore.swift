import AppKit
import Foundation
import Observation
import RomsBoxModels
import RomsBoxEmulation

/// Detected RetroArch install + core index, refreshed on demand (after an
/// install, or the manual "Refresh" button — no filesystem watching).
///
/// Cores are indexed from both the Emulation folder's `Cores` (where
/// `EmulatorInstaller` puts them) and RetroArch's own directory, with
/// `.info` files read from either place.
@Observable
@MainActor
final class RetroArchSettingsStore {
    private static let installPathKey = "retroArchInstallPath"
    private let userDefaults: UserDefaults
    /// RetroArch launches read their config/BIOS/save paths from here.
    let emulationFolderStore: EmulationFolderStore

    var installURL: URL {
        didSet { userDefaults.set(installURL.path, forKey: Self.installPathKey) }
    }

    private(set) var cores: [RetroArchCoreInfo] = []
    /// Every core libretro publishes for this Mac, installed or not.
    private(set) var availableCores: [AvailableCore] = []
    private(set) var isInstalled = false

    init(userDefaults: UserDefaults = .standard, emulationFolderStore: EmulationFolderStore) {
        self.userDefaults = userDefaults
        self.emulationFolderStore = emulationFolderStore
        let savedPath = userDefaults.string(forKey: Self.installPathKey)
        self.installURL = savedPath.map { URL(fileURLWithPath: $0) } ?? RetroArchInstallation.defaultAppURL
        refresh()
        // Picks up cores installed outside RomsBox (RetroArch's Online
        // Updater, or a dylib dropped into Emulation/Cores) as soon as the
        // user comes back — scanning two folders is cheap.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        // A RetroArch that RomsBox installed into ~/Applications (when
        // /Applications isn't writable) should be found without the user
        // having to point at it.
        if !RetroArchInstallation.isInstalled(appURL: installURL),
           let found = Self.knownInstallLocations.first(where: { RetroArchInstallation.isInstalled(appURL: $0) }) {
            installURL = found
        }
        isInstalled = RetroArchInstallation.isInstalled(appURL: installURL)

        let folder = emulationFolderStore.folder
        cores = RetroArchCoreIndex.scan(
            coresDirectories: [folder.cores, RetroArchInstallation.coresDirectoryURL],
            infoDirectories: [folder.coreInfo, RetroArchInstallation.infoDirectoryURL]
        )
        availableCores = AvailableCoreIndex.scan(infoDirectory: folder.coreInfo)
    }

    func availableCores(for canonicalID: CanonicalSystemID) -> [AvailableCore] {
        availableCores.filter { $0.systems.contains(canonicalID) }
    }

    private static var knownInstallLocations: [URL] {
        [
            RetroArchInstallation.defaultAppURL,
            EmulatorInstaller.retroArchInstallDirectory.appending(path: "RetroArch.app"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/RetroArch.app")
        ]
    }

    /// Installed cores that run `canonicalID`, per their `.info` files'
    /// full system list (plus the catalog, as a fallback for a core whose
    /// info file is missing its `database` field).
    func cores(for canonicalID: CanonicalSystemID) -> [RetroArchCoreInfo] {
        cores.filter {
            $0.systems.contains(canonicalID)
                || EmulatorCatalog.systems(forCore: $0.coreIdentifier).contains(canonicalID)
        }
    }

    func core(withIdentifier identifier: String) -> RetroArchCoreInfo? {
        cores.first { $0.coreIdentifier == identifier }
    }

    var binaryURL: URL { RetroArchInstallation.binaryURL(appURL: installURL) }
}
