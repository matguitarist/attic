import Foundation
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

    /// Writes `<destination>/Attic Backup <date>.zip` and trims the folder
    /// to the newest `keptCount` backups. Returns the zip.
    public static func create(from emulationRoot: URL, to destination: URL, date: Date = .now) throws -> URL {
        let fileManager = FileManager.default
        let folders = folderNames.filter { fileManager.fileExists(atPath: emulationRoot.appending(path: $0).path) }
        guard !folders.isEmpty else { throw BackupError.nothingToBackUp }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let zip = destination.appending(path: "\(namePrefix)\(formatter.string(from: date)).zip")
        let partial = destination.appending(path: ".\(zip.lastPathComponent).partial")
        try? fileManager.removeItem(at: partial)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = emulationRoot
        process.arguments = ["-r", "-q", "-y", partial.path] + folders + ["-x", "*.DS_Store"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, fileManager.fileExists(atPath: partial.path) else {
            try? fileManager.removeItem(at: partial)
            throw BackupError.zipFailed
        }
        try fileManager.moveItem(at: partial, to: zip)
        prune(destination)
        return zip
    }

    /// The backups in `folder`, newest first.
    public static func backups(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(namePrefix) && $0.pathExtension.lowercased() == "zip" }
            // The date in the name sorts as text.
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Moves all but the newest `keptCount` backups to the Trash.
    static func prune(_ folder: URL) {
        for old in backups(in: folder).dropFirst(keptCount) {
            try? FileManager.default.trashItem(at: old, resultingItemURL: nil)
        }
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
