import Foundation
import Testing
@testable import AtticLibraryScanning

struct MediaTidierTests {
    /// `Emulation/` with a ROMs root, media and gamelists beside it.
    private let base: URL
    private var roms: URL { base.appending(path: "ROMs") }
    private var media: URL { base.appending(path: "downloaded_media") }
    private var gamelists: URL { base.appending(path: "gamelists") }

    init() throws {
        base = FileManager.default.temporaryDirectory.appending(path: "MediaTidierTests-\(UUID().uuidString)")
    }

    private func touch(_ url: URL, _ text: String = "x") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test func emptySystemFoldersGoWithTheirMediaAndGamelists() throws {
        try touch(roms.appending(path: "snes/Super Mario World (USA).sfc"))
        try touch(roms.appending(path: "steam/_sysinfo.txt"))
        try touch(roms.appending(path: "kodi/systeminfo.txt"))
        try FileManager.default.createDirectory(at: roms.appending(path: "themes"), withIntermediateDirectories: true)
        try touch(media.appending(path: "steam/covers/Game.png"))
        try touch(gamelists.appending(path: "steam/gamelist.xml"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let trashed = Set(plan.trash.map(\.lastPathComponent))
        #expect(trashed.isSuperset(of: ["steam", "kodi", "themes"]))
        #expect(!plan.trash.contains { $0.lastPathComponent == "snes" })
        #expect(plan.trash.contains { $0.path.hasSuffix("downloaded_media/steam") })
        #expect(plan.trash.contains { $0.path.hasSuffix("gamelists/steam") })
    }

    @Test func batoceraMediaIsRenamedIntoDownloadedMedia() throws {
        let neogeo = roms.appending(path: "neogeo")
        try touch(neogeo.appending(path: "2020bb.zip"))
        try touch(neogeo.appending(path: "images/2020bb-boxart.png"))
        try touch(neogeo.appending(path: "images/2020bb-thumb.png"))
        try touch(neogeo.appending(path: "images/2020bb-image.png"))
        try touch(neogeo.appending(path: "images/2020bb-marquee.png"))
        try touch(neogeo.appending(path: "images/gone-boxart.png"))
        try touch(neogeo.appending(path: "videos/2020bb-video.mp4"))
        try touch(neogeo.appending(path: "manuals/2020bb-manual.pdf"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let moves = Dictionary(uniqueKeysWithValues: plan.moves.map { ($0.from.lastPathComponent, $0.to.path(percentEncoded: false)) })
        let target = media.appending(path: "neogeo").path(percentEncoded: false)
        #expect(moves["2020bb-boxart.png"] == target + "/covers/2020bb.png")
        #expect(moves["2020bb-image.png"] == target + "/screenshots/2020bb.png")
        #expect(moves["2020bb-video.mp4"] == target + "/videos/2020bb.mp4")
        #expect(moves["2020bb-manual.pdf"] == target + "/manuals/2020bb.pdf")
        // A thumb only stands in for missing box art; marquees and art for
        // games that aren't there stay behind and go with the folder.
        #expect(moves["2020bb-thumb.png"] == nil)
        #expect(moves["2020bb-marquee.png"] == nil)
        #expect(moves["gone-boxart.png"] == nil)
        #expect(Set(plan.trash.map(\.lastPathComponent)).isSuperset(of: ["images", "videos", "manuals"]))
        #expect(plan.compress.map(\.lastPathComponent) == ["2020bb.png"])

        MediaTidier.apply(plan)
        #expect(exists(media.appending(path: "neogeo/videos/2020bb.mp4")))
        #expect(!exists(neogeo.appending(path: "images")))
        #expect(exists(neogeo.appending(path: "2020bb.zip")))
    }

    @Test func thumbFillsInForMissingBoxArt() throws {
        try touch(roms.appending(path: "cps1/1941.zip"))
        try touch(roms.appending(path: "cps1/images/1941-thumb.png"))
        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.moves.map(\.to.lastPathComponent) == ["1941.png"])
        #expect(plan.moves.first?.to.deletingLastPathComponent().lastPathComponent == "covers")
    }

    @Test func unusedKindsAndOrphansGo() throws {
        try touch(roms.appending(path: "snes/Game (USA).sfc"))
        try touch(roms.appending(path: "snes/Sub/Other (USA).sfc"))
        try touch(media.appending(path: "snes/covers/Game (USA).webp"))
        try touch(media.appending(path: "snes/covers/Sub/Other (USA).webp"))
        try touch(media.appending(path: "snes/covers/Game (USA)_240.jpg"))
        try touch(media.appending(path: "snes/videos/Gone (USA).mp4"))
        try touch(media.appending(path: "snes/fanart/Game (USA).png"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let trashed = Set(plan.trash.map(\.lastPathComponent))
        #expect(trashed == ["Game (USA)_240.jpg", "Gone (USA).mp4", "fanart"])
        // Already compact, so not recompressed.
        #expect(plan.compress.isEmpty)
    }

    @Test func leftoversOfOtherAppsGo() throws {
        let cps2 = roms.appending(path: "cps2")
        try touch(cps2.appending(path: "sf2.zip"))
        try touch(cps2.appending(path: "gamelist_ARRM.xml"))
        try touch(cps2.appending(path: "gamelist_tempo_old.xml"))
        try touch(cps2.appending(path: "readme.txt"))
        try touch(cps2.appending(path: "_sysinfo.txt"))
        try FileManager.default.createDirectory(at: cps2.appending(path: "html_arrm/overlays"), withIntermediateDirectories: true)
        try touch(roms.appending(path: "systems.txt"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let trashed = Set(plan.trash.map(\.lastPathComponent))
        #expect(trashed == ["gamelist_ARRM.xml", "gamelist_tempo_old.xml", "readme.txt", "html_arrm", "systems.txt"])
    }

    @Test func colocatedGamelistMovesWithoutMediaPaths() throws {
        let cps3 = roms.appending(path: "cps3")
        try touch(cps3.appending(path: "sfiii.zip"))
        try touch(cps3.appending(path: "gamelist.xml"), """
        <gameList>
        \t<game>
        \t\t<path>./sfiii.zip</path>
        \t\t<name>Street Fighter III</name>
        \t\t<image>./images/sfiii-image.png</image>
        \t\t<thumbnail>./images/sfiii-thumb.png</thumbnail>
        \t\t<marquee />
        \t</game>
        </gameList>
        """)

        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.gamelists.map(\.to.path) == [gamelists.appending(path: "cps3/gamelist.xml").path])
        MediaTidier.apply(plan)

        let moved = try String(contentsOf: gamelists.appending(path: "cps3/gamelist.xml"), encoding: .utf8)
        #expect(moved == "<gameList>\n\t<game>\n\t\t<path>./sfiii.zip</path>\n\t\t<name>Street Fighter III</name>\n\t</game>\n</gameList>")
        #expect(!exists(cps3.appending(path: "gamelist.xml")))
    }

    @Test func existingESDEGamelistWins() throws {
        try touch(roms.appending(path: "nes/Game.nes"))
        try touch(roms.appending(path: "nes/gamelist.xml"))
        try touch(gamelists.appending(path: "nes/gamelist.xml"))
        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.gamelists.isEmpty)
        #expect(plan.trash.map(\.lastPathComponent) == ["gamelist.xml"])
    }

    @Test func aTidyFolderHasNothingToDo() throws {
        try touch(roms.appending(path: "snes/Game.sfc"))
        try touch(roms.appending(path: "snes/_sysinfo.txt"))
        try touch(media.appending(path: "snes/covers/Game.heic"))
        try touch(gamelists.appending(path: "snes/gamelist.xml"))
        #expect(MediaTidier.plan(romsRoots: [roms]).isEmpty)
    }

    @Test func gamelistsLoseStalePathsAndMissingGames() throws {
        try touch(roms.appending(path: "cps1/1941.zip"))
        try touch(gamelists.appending(path: "cps1/gamelist.xml"), """
        <gameList>
        \t<game id="1">
        \t\t<path>./1941.zip</path>
        \t\t<screenshot>./images/1941-image.png</screenshot>
        \t</game>
        \t<game>
        \t\t<path>./gone &amp; away.zip</path>
        \t</game>
        </gameList>
        """)
        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.gamelists.count == 1)
        MediaTidier.apply(plan)
        let cleaned = try String(contentsOf: gamelists.appending(path: "cps1/gamelist.xml"), encoding: .utf8)
        #expect(cleaned == "<gameList>\n\t<game id=\"1\">\n\t\t<path>./1941.zip</path>\n\t</game>\n</gameList>")
        #expect(MediaTidier.plan(romsRoots: [roms]).isEmpty)
    }

    @Test func emptyGamelistFolderGoes() throws {
        try touch(roms.appending(path: "gba/Game.gba"))
        try touch(gamelists.appending(path: "gba/.DS_Store"))
        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.trash.map(\.lastPathComponent) == ["gba"])
    }

    @Test func palettePNGsAreLeftAsTheyAre() throws {
        try touch(roms.appending(path: "snes/Game.sfc"))
        try touch(roms.appending(path: "snes/Other.sfc"))
        // A PNG header up to IHDR's colour type: 3 (palette), then 6 (RGBA).
        func png(colourType: UInt8) -> Data {
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
                  0, 0, 0, 1, 0, 0, 0, 1, 8, colourType, 0, 0, 0])
        }
        try FileManager.default.createDirectory(at: media.appending(path: "snes/covers"), withIntermediateDirectories: true)
        try png(colourType: 3).write(to: media.appending(path: "snes/covers/Game.png"))
        try png(colourType: 6).write(to: media.appending(path: "snes/covers/Other.png"))
        #expect(MediaTidier.plan(romsRoots: [roms]).compress.map(\.lastPathComponent) == ["Other.png"])
    }

    @Test func storeReplacesTheEarlierFile() throws {
        let snes = roms.appending(path: "snes")
        try touch(media.appending(path: "snes/screenshots/Game.png"))
        let url = try MediaFolder.store(Data("new".utf8), fileExtension: "JPG", forSystemFolder: snes, romRelativePath: "Game.sfc", kind: .screenshots)
        #expect(url.path == media.appending(path: "snes/screenshots/Game.jpg").path)
        #expect(!exists(media.appending(path: "snes/screenshots/Game.png")))
    }
}
