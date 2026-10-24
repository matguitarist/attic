import Foundation
import Testing
@testable import AtticLibraryScanning

struct MediaFoldersTests {
    @Test func makesEachSystemsMediaFoldersOnce() throws {
        let emulation = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: emulation) }
        let roms = emulation.appending(path: "ROMs", directoryHint: .isDirectory)
        for system in ["snes", "steam", "notasystem"] {
            try FileManager.default.createDirectory(at: roms.appending(path: system), withIntermediateDirectories: true)
        }

        let made = MediaFolder.createFolders(romsRoots: [roms], created: [])
        let media = emulation.appending(path: "Media")
        #expect(FileManager.default.fileExists(atPath: media.appending(path: "snes/physicalmedia").path))
        #expect(FileManager.default.fileExists(atPath: media.appending(path: "snes/2dboxes").path))
        #expect(FileManager.default.fileExists(atPath: media.appending(path: "steam/2dboxes").path))
        #expect(!FileManager.default.fileExists(atPath: media.appending(path: "steam/physicalmedia").path))
        #expect(!FileManager.default.fileExists(atPath: media.appending(path: "notasystem").path))
        #expect(made.contains("snes/physicalmedia"))

        // One deleted since stays deleted.
        try FileManager.default.removeItem(at: media.appending(path: "snes/fanart"))
        #expect(MediaFolder.createFolders(romsRoots: [roms], created: made).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: media.appending(path: "snes/fanart").path))
    }

    @Test func marqueesAreForArcadeSystems() {
        #expect(MediaFolder.kinds(for: .cps2).contains(.marquees))
        #expect(!MediaFolder.kinds(for: .snes).contains(.marquees))
        #expect(MediaFolder.kinds(for: .snes).contains(.bezels))
    }

    @Test func movesCoversTo2DBoxes() throws {
        let emulation = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: emulation) }
        let roms = emulation.appending(path: "ROMs", directoryHint: .isDirectory)
        let media = emulation.appending(path: "Media", directoryHint: .isDirectory)
        func touch(_ path: String) throws {
            let url = media.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        try FileManager.default.createDirectory(at: roms, withIntermediateDirectories: true)
        // A plain rename, over an empty 2dboxes made since.
        try touch("snes/covers/Mario.heic")
        try FileManager.default.createDirectory(at: media.appending(path: "snes/2dboxes"), withIntermediateDirectories: true)
        // Both with files: the new one keeps its own.
        try touch("nes/covers/Zelda.heic")
        try touch("nes/covers/Metroid.heic")
        try touch("nes/2dboxes/Zelda.heic")

        let renamed = MediaFolder.adoptRenamedKinds(romsRoots: [roms])
        #expect(renamed.allSatisfy { $0.from.lastPathComponent == "covers" && $0.to.lastPathComponent == "2dboxes" })
        #expect(renamed.count == 2)
        let exists = { (path: String) in FileManager.default.fileExists(atPath: media.appending(path: path).path) }
        #expect(exists("snes/2dboxes/Mario.heic"))
        #expect(!exists("snes/covers"))
        #expect(exists("nes/2dboxes/Metroid.heic"))
        #expect((try? String(contentsOf: media.appending(path: "nes/2dboxes/Zelda.heic"), encoding: .utf8)) == "nes/2dboxes/Zelda.heic")
        // Its own Zelda stays behind, for the tidy-up to compare.
        #expect(exists("nes/covers/Zelda.heic"))
        #expect(MediaFolder.adoptRenamedKinds(romsRoots: [roms]).count == 1)
    }
}
