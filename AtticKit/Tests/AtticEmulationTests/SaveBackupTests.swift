import Foundation
import Testing
import ArchiveKit
@testable import AtticEmulation

struct SaveBackupTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "Backup-\(UUID().uuidString)")

    private func touch(_ path: String) throws {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    @Test func zipsSavesStatesCollectionsAndGamelists() async throws {
        try touch("Emulation/Saves/snes/Zelda.srm")
        try touch("Emulation/States/snes/Zelda.state1")
        try touch("Emulation/Collections/Zelda/collection.json")
        try touch("Emulation/Gamelists/snes/gamelist.xml")
        try touch("Emulation/ROMs/snes/Zelda.sfc")
        let zip = try await SaveBackup.create(from: base.appending(path: "Emulation"), to: base.appending(path: "Backups"), disposal: .delete)
        #expect(zip.lastPathComponent.hasPrefix("Attic Backup "))

        let names = try Zip.names(zip)
        #expect(names.contains("Saves/snes/Zelda.srm") && names.contains("States/snes/Zelda.state1"))
        #expect(names.contains("Collections/Zelda/collection.json") && names.contains("Gamelists/snes/gamelist.xml"))
        #expect(!names.contains { $0.hasPrefix("ROMs") })
        // Nothing half-written is left beside it.
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.appending(path: "Backups").path) == [zip.lastPathComponent])
    }

    @Test func keepsTheNewestFive() async throws {
        try touch("Emulation/Saves/a.srm")
        let destination = base.appending(path: "Backups")
        for day in 1...7 {
            _ = try await SaveBackup.create(from: base.appending(path: "Emulation"), to: destination,
                                            date: Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200), disposal: .delete)
        }
        let kept = SaveBackup.backups(in: destination)
        #expect(kept.count == 5)
        #expect(kept.first?.lastPathComponent.contains("1970-01-08") == true)
    }

    @Test func anEmptyEmulationFolderHasNothingToBackUp() async throws {
        try touch("Emulation/ROMs/snes/Zelda.sfc")
        await #expect(throws: SaveBackup.BackupError.nothingToBackUp) {
            try await SaveBackup.create(from: base.appending(path: "Emulation"), to: base.appending(path: "Backups"), disposal: .delete)
        }
    }

    @Test func weeklyBackupsComeDue() {
        let now = Date()
        #expect(SaveBackup.isDue(lastBackup: nil, now: now))
        #expect(!SaveBackup.isDue(lastBackup: now.addingTimeInterval(-86_400), now: now))
        #expect(SaveBackup.isDue(lastBackup: now.addingTimeInterval(-8 * 86_400), now: now))
    }
}
