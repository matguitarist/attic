import Foundation
import Observation
import RomsBoxEmulation

/// Where the user's Emulation folder lives (see `EmulationFolder`), and the
/// one-time setup that fills it in: creating the layout, copying BIOS files
/// over from RetroArch's old system folder, and starting RomsBox's RetroArch
/// config from the user's existing one.
@Observable
@MainActor
final class EmulationFolderStore {
    private static let rootPathKey = "emulationFolderPath"
    private static let importedRetroArchBIOSKey = "didImportRetroArchBIOS"

    private let userDefaults: UserDefaults

    private(set) var folder: EmulationFolder
    /// What the last `prepare()` copied in, for showing the user.
    private(set) var lastImportSummary: String?
    private(set) var lastError: String?

    init(userDefaults: UserDefaults = .standard, romsRoots: [URL]) {
        self.userDefaults = userDefaults
        let root = userDefaults.string(forKey: Self.rootPathKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? EmulationFolder.defaultRoot(romsRoots: romsRoots)
        folder = EmulationFolder(root: root)
    }

    func setRoot(_ url: URL) {
        folder = EmulationFolder(root: url)
        userDefaults.set(url.path, forKey: Self.rootPathKey)
        // A new folder starts without the user's BIOS files, so offer the
        // import again.
        userDefaults.removeObject(forKey: Self.importedRetroArchBIOSKey)
        prepare(romsRoots: [])
    }

    /// Safe to call on every launch: only creates what's missing and only
    /// imports BIOS files once per folder. Does nothing until a ROMs folder
    /// has been chosen — the default location is derived from it, and
    /// committing to `~/Emulation` on a first launch before that would put
    /// the folder in the wrong place for good.
    func prepare(romsRoots: [URL]) {
        if userDefaults.string(forKey: Self.rootPathKey) == nil {
            guard !romsRoots.isEmpty else { return }
            folder = EmulationFolder(root: EmulationFolder.defaultRoot(romsRoots: romsRoots))
        }
        do {
            try folder.createStructure()
            userDefaults.set(folder.root.path, forKey: Self.rootPathKey)
            try folder.seedRetroArchConfig(from: RetroArchInstallation.configFileURL)

            if !userDefaults.bool(forKey: Self.importedRetroArchBIOSKey) {
                let source = RetroArchInstallation.systemDirectoryURL()
                // Copy, never move: RetroArch opened on its own still reads
                // its original system folder.
                let copied = try EmulationFolder.copyMissingFiles(from: source, to: folder.bios)
                userDefaults.set(true, forKey: Self.importedRetroArchBIOSKey)
                if !copied.isEmpty {
                    lastImportSummary = String(localized: "Copied \(copied.count) BIOS files from \((source.path as NSString).abbreviatingWithTildeInPath).")
                }
            }
            lastError = nil
        } catch {
            lastError = String(localized: "Couldn't set up the Emulation folder: \(error.localizedDescription)")
        }
    }

    var displayPath: String { (folder.root.path as NSString).abbreviatingWithTildeInPath }
}
