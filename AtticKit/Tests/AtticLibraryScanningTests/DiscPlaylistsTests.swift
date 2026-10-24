import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

struct DiscPlaylistsTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "Discs-\(UUID().uuidString)")

    private func touch(_ path: String) throws -> URL {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func readsDiscTags() {
        #expect(DiscPlaylists.disc(in: "Final Fantasy VII (USA) (Disc 2)")! == ("Final Fantasy VII (USA)", 2))
        #expect(DiscPlaylists.disc(in: "Policenauts (Japan) (Disk 1 of 3)")! == ("Policenauts (Japan)", 1))
        #expect(DiscPlaylists.disc(in: "Tekken 3 (USA)") == nil)
    }

    @Test func readsTheTracksOfCueAndGdiSheets() {
        #expect(DiscPlaylists.partName(#"FILE "Game (Track 1).bin" BINARY"#, in: "cue") == "Game (Track 1).bin")
        #expect(DiscPlaylists.partName("  TRACK 01 MODE2/2352", in: "cue") == nil)
        #expect(DiscPlaylists.partName("3", in: "gdi") == nil)
        #expect(DiscPlaylists.partName(#"1 0 4 2352 "track01.bin" 0"#, in: "gdi") == "track01.bin")
        #expect(DiscPlaylists.partName("2 756 0 2352 track02.raw 0", in: "gdi") == "track02.raw")
    }

    @Test func makesOnePlaylistPerSetAndHidesItsDiscs() throws {
        for disc in 1...3 {
            _ = try touch("ROMs/psx/Final Fantasy VII (USA) (Disc \(disc)).cue")
            _ = try touch("ROMs/psx/Final Fantasy VII (USA) (Disc \(disc)).bin")
        }
        _ = try touch("ROMs/psx/Metal Gear Solid (USA) (Disc 1).chd")
        _ = try touch("ROMs/psx/Metal Gear Solid (USA) (Disc 2).chd")
        _ = try touch("ROMs/psx/Tekken 3 (USA).chd")
        _ = try touch("Media/psx/2dboxes/Final Fantasy VII (USA) (Disc 1).heic")
        let psx = base.appending(path: "ROMs/psx")

        #expect(DiscPlaylists.createMissing(romsRoots: [base.appending(path: "ROMs")]) == 2)
        let ff7 = try String(contentsOf: psx.appending(path: "Final Fantasy VII (USA).m3u"), encoding: .utf8)
        #expect(ff7 == "Final Fantasy VII (USA) (Disc 1).cue\nFinal Fantasy VII (USA) (Disc 2).cue\nFinal Fantasy VII (USA) (Disc 3).cue\n")
        // The game takes disc 1's cover.
        #expect(FileManager.default.fileExists(atPath: base.appending(path: "Media/psx/2dboxes/Final Fantasy VII (USA).heic").path))
        // Once there, it isn't made again.
        #expect(DiscPlaylists.missing(in: psx).isEmpty)
        #expect(DiscPlaylists.listedFiles(in: psx).contains("Metal Gear Solid (USA) (Disc 2).chd"))
    }

    @Test func readsPlaylistsMadeOnWindows() {
        #expect(DiscPlaylists.partName(#"\MultiDisc\Game (USA) (Disc 1).chd"#, in: "m3u") == "MultiDisc/Game (USA) (Disc 1).chd")
        #expect(DiscPlaylists.partName(#".\MultiDisc\Game (Disc 2).rvz"#, in: "m3u") == "MultiDisc/Game (Disc 2).rvz")
        #expect(DiscPlaylists.partName("./Game (Disc 1).chd", in: "m3u") == "Game (Disc 1).chd")
        #expect(DiscPlaylists.partName("# a comment", in: "m3u") == nil)
        #expect(DiscPlaylists.macText(of: "\\MultiDisc\\A (Disc 1).chd\r\n\\MultiDisc\\A (Disc 2).chd\r\n")
                == "MultiDisc/A (Disc 1).chd\nMultiDisc/A (Disc 2).chd\n")
        #expect(DiscPlaylists.macText(of: "A (Disc 1).chd\nA (Disc 2).chd\n") == nil)
    }

    /// RetroBat's layout: the playlist at the top, its discs in MultiDisc.
    @Test func discsInAMultiDiscFolderBelongToTheirPlaylist() throws {
        let psx = base.appending(path: "ROMs/psx")
        _ = try touch("ROMs/psx/MultiDisc/Wild Arms 2 (USA) (Disc 1).cue")
        _ = try touch("ROMs/psx/MultiDisc/Wild Arms 2 (USA) (Disc 1).bin")
        _ = try touch("ROMs/psx/MultiDisc/Wild Arms 2 (USA) (Disc 2).chd")
        try Data(#"FILE "Wild Arms 2 (USA) (Disc 1).bin" BINARY"#.utf8).write(to: psx.appending(path: "MultiDisc/Wild Arms 2 (USA) (Disc 1).cue"))
        try Data("\\MultiDisc\\Wild Arms 2 (USA) (Disc 1).cue\r\n\\MultiDisc\\Wild Arms 2 (USA) (Disc 2).chd\r\n".utf8)
            .write(to: psx.appending(path: "Wild Arms 2 (MultiDisc).m3u"))
        // A set there with no playlist yet.
        _ = try touch("ROMs/psx/MultiDisc/Legend of Dragoon (USA) (Disc 1).chd")
        _ = try touch("ROMs/psx/MultiDisc/Legend of Dragoon (USA) (Disc 2).chd")

        let listed = DiscPlaylists.listedFiles(in: psx)
        #expect(listed.isSuperset(of: ["MultiDisc/Wild Arms 2 (USA) (Disc 1).cue", "MultiDisc/Wild Arms 2 (USA) (Disc 1).bin",
                                       "MultiDisc/Wild Arms 2 (USA) (Disc 2).chd"]))
        // Its discs are listed, under another name than the playlist's.
        #expect(DiscPlaylists.missing(in: psx).map(\.url.lastPathComponent) == ["Legend of Dragoon (USA).m3u"])

        let plan = DiscPlaylistPlan.plan(romsRoots: [base.appending(path: "ROMs")])
        #expect(plan.windows.map(\.lastPathComponent) == ["Wild Arms 2 (MultiDisc).m3u"])
        #expect(plan.broken.isEmpty)
        #expect(DiscPlaylistPlan.apply(plan) == (1, 1))
        #expect(try String(contentsOf: psx.appending(path: "Legend of Dragoon (USA).m3u"), encoding: .utf8)
                == "MultiDisc/Legend of Dragoon (USA) (Disc 1).chd\nMultiDisc/Legend of Dragoon (USA) (Disc 2).chd\n")
        #expect(try String(contentsOf: psx.appending(path: "Wild Arms 2 (MultiDisc).m3u"), encoding: .utf8)
                == "MultiDisc/Wild Arms 2 (USA) (Disc 1).cue\nMultiDisc/Wild Arms 2 (USA) (Disc 2).chd\n")
        #expect(DiscPlaylistPlan.plan(romsRoots: [base.appending(path: "ROMs")]).isEmpty)
    }

    @Test func aPlaylistNamingAbsentDiscsIsReported() throws {
        let psx = base.appending(path: "ROMs/psx")
        _ = try touch("ROMs/psx/Gone (USA) (Disc 1).chd")
        try FileManager.default.createDirectory(at: psx, withIntermediateDirectories: true)
        try Data("Gone (USA) (Disc 1).chd\nGone (USA) (Disc 2).chd\n".utf8).write(to: psx.appending(path: "Gone (USA).m3u"))
        let plan = DiscPlaylistPlan.plan(romsRoots: [base.appending(path: "ROMs")])
        #expect(plan.broken.map(\.playlist.lastPathComponent) == ["Gone (USA).m3u"])
        #expect(plan.broken.first?.absent == ["Gone (USA) (Disc 2).chd"])
    }
}
