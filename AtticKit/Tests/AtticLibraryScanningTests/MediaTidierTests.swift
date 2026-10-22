import Foundation
import CoreGraphics
import Testing
@testable import AtticLibraryScanning

struct MediaTidierTests {
    /// `Emulation/` with a ROMs root, media and gamelists beside it.
    private let base: URL
    private var roms: URL { base.appending(path: "ROMs") }
    private var media: URL { base.appending(path: "Media") }
    private var gamelists: URL { base.appending(path: "Gamelists") }

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
        // Known systems' folders stay, empty or not; other apps' notes go.
        try touch(roms.appending(path: "x68000/_sysinfo.txt"))
        try touch(roms.appending(path: "pc98/systeminfo.txt"))
        try FileManager.default.createDirectory(at: roms.appending(path: "themes"), withIntermediateDirectories: true)
        try touch(media.appending(path: "steam/covers/Game.png"))
        try touch(gamelists.appending(path: "steam/gamelist.xml"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let trashed = Set(plan.trash.map(\.lastPathComponent))
        #expect(trashed.isSuperset(of: ["steam", "kodi", "themes"]))
        #expect(!plan.trash.contains { $0.lastPathComponent == "snes" })
        #expect(!plan.trash.contains { $0.lastPathComponent == "x68000" || $0.lastPathComponent == "pc98" })
        #expect(plan.trash.contains { $0.path.hasSuffix("pc98/systeminfo.txt") })
        #expect(plan.trash.contains { $0.path.hasSuffix("Media/steam") })
        #expect(plan.trash.contains { $0.path.hasSuffix("Gamelists/steam") })
    }

    @Test func batoceraMediaIsRenamedIntoDownloadedMedia() throws {
        let neogeo = roms.appending(path: "neogeo")
        try touch(neogeo.appending(path: "2020bb.zip"))
        try touch(neogeo.appending(path: "images/2020bb-boxart.png"))
        try touch(neogeo.appending(path: "images/2020bb-thumb.png"))
        try touch(neogeo.appending(path: "images/2020bb-image.png"))
        try touch(neogeo.appending(path: "images/2020bb-marquee.png"))
        try touch(neogeo.appending(path: "images/2020bb-fanart.jpg"))
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
        #expect(moves["2020bb-marquee.png"] == target + "/logos/2020bb.png")
        #expect(moves["2020bb-fanart.jpg"] == target + "/fanart/2020bb.jpg")
        // A thumb only stands in for missing box art; art for games that
        // aren't there stays behind and goes with the folder.
        #expect(moves["2020bb-thumb.png"] == nil)
        #expect(moves["gone-boxart.png"] == nil)
        #expect(Set(plan.trash.map(\.lastPathComponent)).isSuperset(of: ["images", "videos", "manuals"]))
        #expect(Set(plan.compress.map(\.lastPathComponent)) == ["2020bb.png", "2020bb.jpg"])

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
        try touch(media.appending(path: "snes/backcovers/Game (USA).png"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let trashed = Set(plan.trash.map(\.lastPathComponent))
        #expect(trashed == ["Game (USA)_240.jpg", "Gone (USA).mp4", "backcovers"])
        // Already compact, so not recompressed.
        #expect(plan.compress.isEmpty)
    }

    @Test func threeDBoxesStay() throws {
        try touch(roms.appending(path: "snes/Game (USA).sfc"))
        try touch(media.appending(path: "snes/3dboxes/Game (USA).webp"))
        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.trash.isEmpty)
    }

    @Test func mixImagesAndTitleScreensOnlyStayAsStandIns() throws {
        try touch(roms.appending(path: "snes/Covered.sfc"))
        try touch(roms.appending(path: "snes/Bare.sfc"))
        try touch(media.appending(path: "snes/covers/Covered.heic"))
        try touch(media.appending(path: "snes/miximages/Covered.webp"))
        try touch(media.appending(path: "snes/miximages/Bare.webp"))
        try touch(media.appending(path: "snes/titlescreens/Bare.png"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let moves = plan.moves.map { "\($0.to.deletingLastPathComponent().lastPathComponent)/\($0.to.lastPathComponent)" }
        #expect(Set(moves) == ["covers/Bare.webp", "screenshots/Bare.png"])
        #expect(Set(plan.trash.map(\.lastPathComponent)).isSuperset(of: ["miximages", "titlescreens"]))
        MediaTidier.apply(plan)
        #expect(exists(media.appending(path: "snes/covers/Bare.webp")))
        #expect(!exists(media.appending(path: "snes/miximages")))
    }

    @Test func leavingOutStepsKeepsWhatTheyNeed() throws {
        let neogeo = roms.appending(path: "neogeo")
        try touch(neogeo.appending(path: "2020bb.zip"))
        try touch(neogeo.appending(path: "images/2020bb-boxart.png"))
        try touch(neogeo.appending(path: "readme.txt"))
        try touch(media.appending(path: "neogeo/backcovers/2020bb.png"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.steps == [.moveMedia, .compressCovers, .trash(.otherApps), .trash(.unshownMedia), .trash(.leftoverMedia)])
        #expect(plan.trashed.first { $0.url.lastPathComponent == "readme.txt" }?.bytes ?? 0 > 0)

        // Without the move, Batocera's images folder stays: its box art
        // would otherwise go to the Trash unmoved.
        let noMove = plan.only([.trash(.otherApps), .trash(.leftoverMedia), .trash(.unshownMedia)])
        #expect(noMove.moves.isEmpty && noMove.compress.isEmpty)
        #expect(Set(noMove.trash.map(\.lastPathComponent)) == ["readme.txt", "backcovers"])

        let onlyReadme = plan.only([.moveMedia, .trash(.otherApps)])
        #expect(onlyReadme.trash.map(\.lastPathComponent) == ["readme.txt"])
        #expect(onlyReadme.moves.count == 1)
    }

    @Test func duplicatesGoWithTheirMediaButNotTheKeptGames() throws {
        try touch(roms.appending(path: "nes/Zelda (USA).nes"))
        try touch(roms.appending(path: "nes/Zelda (Europe).nes"))
        try touch(roms.appending(path: "nes/Runner (USA).nes"))
        try touch(roms.appending(path: "nes/Runner (USA).zip"))
        try touch(media.appending(path: "nes/covers/Zelda (Europe).heic"))
        try touch(media.appending(path: "nes/covers/Zelda (USA).heic"))
        try touch(media.appending(path: "nes/covers/Runner (USA).heic"))

        let plan = MediaTidier.plan(romsRoots: [roms])
        let duplicates = plan.trashed.filter { $0.reason == .duplicates }.map(\.url.lastPathComponent)
        #expect(Set(duplicates) == ["Zelda (Europe).nes", "Zelda (Europe).heic", "Runner (USA).zip"])
        #expect(plan.keptCopies.values.map(\.lastPathComponent).sorted() == ["Runner (USA).nes", "Zelda (USA).nes"])
        // Off unless asked for.
        #expect(plan.only(Set(plan.steps).subtracting([.trash(.duplicates)])).trashed.isEmpty)
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

    @Test func coversHEICDoesntShrinkAreLeftAfterOneTry() throws {
        try touch(roms.appending(path: "snes/Game.sfc"))
        try touch(roms.appending(path: "snes/Other.sfc"))
        // A PNG header up to IHDR's colour type: 3 (palette), then 6 (RGBA).
        // Both are tried; neither gets smaller, so neither is tried again.
        func png(colourType: UInt8) -> Data {
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
                  0, 0, 0, 1, 0, 0, 0, 1, 8, colourType, 0, 0, 0])
        }
        try FileManager.default.createDirectory(at: media.appending(path: "snes/covers"), withIntermediateDirectories: true)
        try png(colourType: 3).write(to: media.appending(path: "snes/covers/Game.png"))
        try png(colourType: 6).write(to: media.appending(path: "snes/covers/Other.png"))
        let plan = MediaTidier.plan(romsRoots: [roms])
        #expect(plan.compress.map(\.lastPathComponent).sorted() == ["Game.png", "Other.png"])
        #expect(MediaTidier.apply(plan) == 0)
        #expect(exists(media.appending(path: "snes/covers/Game.png")))
        #expect(MediaTidier.plan(romsRoots: [roms]).compress.isEmpty)
    }

    @Test func aCoverWithAHEICBesideItIsntOffered() throws {
        try touch(roms.appending(path: "snes/Game.sfc"))
        try touch(media.appending(path: "snes/covers/Game.png"))
        try touch(media.appending(path: "snes/covers/Game.heic"))
        #expect(MediaTidier.plan(romsRoots: [roms]).compress.isEmpty)
    }

    @Test func storeReplacesTheEarlierFile() throws {
        let snes = roms.appending(path: "snes")
        try touch(media.appending(path: "snes/screenshots/Game.png"))
        let url = try MediaFolder.store(Data("new".utf8), fileExtension: "JPG", forSystemFolder: snes, romRelativePath: "Game.sfc", kind: .screenshots)
        #expect(url.path == media.appending(path: "snes/screenshots/Game.jpg").path)
        #expect(!exists(media.appending(path: "snes/screenshots/Game.png")))
    }
}

struct ManualCompressionTests {
    /// A one-page PDF holding a large noisy scan, stored losslessly so it's
    /// far heavier per page than a real manual.
    private func heavyManual() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Manual-\(UUID().uuidString).pdf")
        let (width, height) = (1700, 2200)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 1
        for index in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 1_103_515_245 &+ 12345
            let noise = UInt8(truncatingIfNeeded: seed >> 16) / 8
            let shade = UInt8((index / 4 / width) * 200 / height) &+ noise
            pixels[index] = shade; pixels[index + 1] = shade; pixels[index + 2] = shade; pixels[index + 3] = 255
        }
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let image = context.makeImage()!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = CGContext(url as CFURL, mediaBox: &box, nil)!
        pdf.beginPage(mediaBox: &box)
        pdf.draw(image, in: box)
        pdf.endPage()
        pdf.closePDF()
        return url
    }

    @Test func heavyScansAreRedoneOnlyOnce() throws {
        let manual = try heavyManual()
        #expect(MediaFolder.manualIsWorthCompressing(manual))
        let replaced = MediaFolder.compressManual(manual)
        #expect(FileManager.default.fileExists(atPath: manual.path))
        // Either way, it's never offered again.
        #expect(!MediaFolder.manualIsWorthCompressing(manual), "replaced: \(replaced)")
    }
}
