import Foundation
import Testing
@testable import AtticEmulation

struct SaveBackupTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "Backup-\(UUID().uuidString)")

    private func touch(_ path: String) throws {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    @Test func zipsSavesStatesCollectionsAndGamelists() throws {
        try touch("Emulation/Saves/snes/Zelda.srm")
        try touch("Emulation/States/snes/Zelda.state1")
        try touch("Emulation/Collections/Zelda/collection.json")
        try touch("Emulation/Gamelists/snes/gamelist.xml")
        try touch("Emulation/ROMs/snes/Zelda.sfc")
        let zip = try SaveBackup.create(from: base.appending(path: "Emulation"), to: base.appending(path: "Backups"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zip.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(names.contains("Saves/snes/Zelda.srm") && names.contains("States/snes/Zelda.state1"))
        #expect(names.contains("Collections/Zelda/collection.json") && names.contains("Gamelists/snes/gamelist.xml"))
        #expect(!names.contains("ROMs"))
    }

    @Test func keepsTheNewestFive() throws {
        try touch("Emulation/Saves/a.srm")
        let destination = base.appending(path: "Backups")
        for day in 1...7 {
            _ = try SaveBackup.create(from: base.appending(path: "Emulation"), to: destination, date: Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200))
        }
        let kept = SaveBackup.backups(in: destination)
        #expect(kept.count == 5)
        #expect(kept.first?.lastPathComponent.contains("1970-01-08") == true)
    }

    @Test func weeklyBackupsComeDue() {
        let now = Date()
        #expect(SaveBackup.isDue(lastBackup: nil, now: now))
        #expect(!SaveBackup.isDue(lastBackup: now.addingTimeInterval(-86_400), now: now))
        #expect(SaveBackup.isDue(lastBackup: now.addingTimeInterval(-8 * 86_400), now: now))
    }
}
