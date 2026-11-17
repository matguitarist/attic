import Foundation
import SwiftData
import AtticEmulation
import AtticPersistence

/// Follows an emulator whose project took a new name (sm2-emu became
/// Keisho): its files move in `EmulationFolder.adoptRenamedEmulators`,
/// and the profiles Attic made for it are pointed at the new app, so the
/// systems that ran it ask for the new one instead of launching the old.
/// Runs at every launch; it does nothing once there's nothing left to move.
enum RenamedEmulatorMigration {
    @MainActor
    static func run(emulationFolder: EmulationFolder, in container: ModelContainer) {
        emulationFolder.adoptRenamedEmulators()
        let context = container.mainContext
        guard let profiles = try? context.fetch(FetchDescriptor<EmulatorProfile>()) else { return }
        let installer = EmulatorInstaller(paths: emulationFolder.installerPaths)
        var changed = false
        for profile in profiles {
            guard let oldID = profile.catalogEmulatorID,
                  let renamed = EmulatorCatalog.renamedEmulators[oldID] else { continue }
            let (oldName, emulator) = renamed
            profile.catalogEmulatorID = emulator.id
            if profile.name == oldName { profile.name = emulator.name }
            profile.argumentTemplate = emulator.argumentTemplate
            profile.executablePath = installer.appDirectory(for: emulator)
                .appending(path: emulator.appBundleName)
                .appending(path: emulator.executableRelativePath).path
            for systemID in emulator.systems where !profile.assignedSystemIDs.contains(systemID) {
                profile.assignedSystemIDs.append(systemID)
            }
            AppLog.post(.info, "\(oldName) is now called \(emulator.name): its profile points at the new app.")
            changed = true
        }
        if changed { try? context.save() }
    }
}
