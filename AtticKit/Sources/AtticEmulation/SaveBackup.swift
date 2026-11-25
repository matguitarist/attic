import Foundation
import ArchiveKit
import AtticModels

/// A zip of what can't be downloaded again: saves, save states,
/// collections and gamelists (scraped descriptions and the like), from
/// the Emulation folder, into a folder of one's choosing. The newest few
/// are kept there.
public enum SaveBackup {
    /// The Emulation folder's folders that are backed up, those there.
    public static let folderNames = ["Saves", "States", EmulationLayout.collections, EmulationLayout.gamelists]
    static let namePrefix = "Attic Backup "
    public static let keptCount = 5

    /// Writes `<destination>/Attic Backup <date>.zip` with ArchiveKit (beside
    /// it first, moved into place when whole) and trims the folder to the
    /// newest `keptCount` backups, the others going to `disposal` (the
    /// Trash). Returns the zip.
    public static func create(from emulationRoot: URL, to destination: URL, date: Date = .now,
                              disposal: Disposal = .trash) async throws -> URL {
        let folders = folderNames.filter { FileManager.default.fileExists(atPath: emulationRoot.appending(path: $0).path) }
        guard !folders.isEmpty else { throw BackupError.nothingToBackUp }
        let backups = BackupFolder(root: destination, disposal: disposal)
        let backup: BackupFolder.Backup
        do {
            // A plain zip, as zip(1) wrote: any tool, on any system, reads it.
            backup = try await backups.backUp(from: emulationRoot, items: folders,
                                              name: namePrefix + BackupFolder.stamp(date), macMetadata: false)
        } catch let error as ArchiveError {
            throw error == .nothingToBackUp ? BackupError.nothingToBackUp : BackupError.zipFailed
        }
        _ = try? backups.prune(keep: keptCount, matching: isBackup)
        return backup.url
    }

    /// The backups in `folder`, newest first.
    public static func backups(in folder: URL) -> [URL] {
        BackupFolder(root: folder).list().filter(isBackup).map(\.url)
    }

    private static func isBackup(_ backup: BackupFolder.Backup) -> Bool {
        backup.name.hasPrefix(namePrefix)
    }

    /// Whether a weekly backup is due.
    public static func isDue(lastBackup: Date?, now: Date = .now) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= 7 * 24 * 3600
    }

    public enum BackupError: Error {
        case nothingToBackUp, zipFailed
    }
}
