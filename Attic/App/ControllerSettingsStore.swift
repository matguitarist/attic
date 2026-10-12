import Foundation
import Observation
import AtticModels

/// The controller settings in effect (Settings › Controller) and the
/// profiles saved from them.
///
/// The current settings live in user defaults; saved profiles live in the
/// Emulation folder (`Config/Attic/controller-profiles.json`), so they
/// travel with it to another Mac like everything else emulation-related.
@Observable
@MainActor
final class ControllerSettingsStore {
    private static let settingsKey = "controllerSettings"
    /// Before controller settings existed, Select + Start had its own
    /// toggle in Settings › General.
    private static let legacyQuitComboKey = "quitGameWithSelectStart"

    /// Built in, can't be deleted.
    static let presets: [ControllerProfile] = [
        ControllerProfile(
            id: UUID(uuidString: "6D1D7A4E-0C55-4C4B-9E43-2B1B6A0C0001")!,
            name: String(localized: "Classic (Xbox, PlayStation)"),
            settings: ControllerSettings(layout: .classic)
        ),
        ControllerProfile(
            id: UUID(uuidString: "6D1D7A4E-0C55-4C4B-9E43-2B1B6A0C0002")!,
            name: String(localized: "Nintendo (Switch)"),
            settings: ControllerSettings(layout: .nintendo)
        )
    ]

    var settings: ControllerSettings {
        didSet { save() }
    }
    private(set) var savedProfiles: [ControllerProfile] = []
    private(set) var lastError: String?

    private let userDefaults: UserDefaults
    private let emulationFolderStore: EmulationFolderStore

    init(userDefaults: UserDefaults = .standard, emulationFolderStore: EmulationFolderStore) {
        self.userDefaults = userDefaults
        self.emulationFolderStore = emulationFolderStore
        if let data = userDefaults.data(forKey: Self.settingsKey),
           let stored = try? JSONDecoder().decode(ControllerSettings.self, from: data) {
            settings = stored
        } else {
            var initial = ControllerSettings.default
            if let quit = userDefaults.object(forKey: Self.legacyQuitComboKey) as? Bool {
                initial.quitWithSelectStart = quit
            }
            settings = initial
        }
        loadProfiles()
    }

    /// The preset or saved profile matching the current settings, if any.
    var matchingProfile: ControllerProfile? {
        (Self.presets + savedProfiles).first { $0.settings == settings }
    }

    func apply(_ profile: ControllerProfile) {
        settings = profile.settings
    }

    /// Saves the current settings under `name`, replacing a saved profile
    /// of the same name.
    func saveCurrentSettings(as name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let index = savedProfiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            savedProfiles[index].settings = settings
        } else {
            savedProfiles.append(ControllerProfile(name: name, settings: settings))
            savedProfiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        writeProfiles()
    }

    func delete(_ profile: ControllerProfile) {
        savedProfiles.removeAll { $0.id == profile.id }
        writeProfiles()
    }

    /// Re-reads the profiles file, e.g. after the Emulation folder moved.
    func loadProfiles() {
        guard let data = try? Data(contentsOf: profilesFile) else {
            savedProfiles = []
            return
        }
        savedProfiles = (try? JSONDecoder().decode([ControllerProfile].self, from: data)) ?? []
    }

    private var profilesFile: URL {
        emulationFolderStore.folder.config.appending(path: "Attic/controller-profiles.json")
    }

    private func writeProfiles() {
        do {
            try FileManager.default.createDirectory(at: profilesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(savedProfiles).write(to: profilesFile, options: .atomic)
            lastError = nil
        } catch {
            lastError = String(localized: "Couldn't save controller profiles: \(error.localizedDescription)")
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: Self.settingsKey)
        }
    }
}
