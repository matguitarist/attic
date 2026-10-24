import Foundation
import Testing
import AtticLibraryScanning
import AtticModels
@testable import AtticEmulation

struct EmuMoviesTests {

    @Test func readsDOSAndUnixListings() {
        let dos = """
        06-01-18  05:18PM             22145735 Atari Lynx (2D Carts)(32assassin 2.0).zip\r
        02-10-25  10:30AM       <DIR>          Atari Lynx (Game Manuals)(EM 1.1)\r
        """
        #expect(EmuMovies.entries(inListing: dos) == [
            .init(name: "Atari Lynx (2D Carts)(32assassin 2.0).zip", isFolder: false, size: 22_145_735, modified: "06-01-18  05:18PM"),
            .init(name: "Atari Lynx (Game Manuals)(EM 1.1)", isFolder: true, size: 0, modified: "02-10-25  10:30AM")
        ])
        let unix = """
        drwxr-xr-x   1 owner group            0 Feb 10  2025 Atari Lynx (Game Manuals)(EM 1.1)
        -rw-r--r--   1 owner group     22145735 Jun  1 17:18 Klax  (USA).pdf
        drwxr-xr-x   1 owner group            0 Feb 10  2025 ..
        """
        #expect(EmuMovies.entries(inListing: unix) == [
            .init(name: "Atari Lynx (Game Manuals)(EM 1.1)", isFolder: true, size: 0, modified: "Feb 10  2025"),
            .init(name: "Klax  (USA).pdf", isFolder: false, size: 22_145_735, modified: "Jun  1 17:18")
        ])
    }

    @Test func keepsListingsUntilTheirFolderChanges() {
        let path = "/Official/Game Manuals/Atari Lynx (Game Manuals)(EM 1.1)/"
        let folder = EmuMovies.Entry(name: "Atari Lynx (Game Manuals)(EM 1.1)", isFolder: true, size: 0, modified: "02-10-25  10:30AM")
        let read = Date(timeIntervalSince1970: 1_800_000_000)
        var cache = EmuMovies.ListingCache()
        #expect(cache.entries(of: path, folder: folder) == nil)
        cache.store([file("Klax (USA).pdf")], of: path, folder: folder, now: read)
        #expect(cache.entries(of: path, folder: folder, now: read + 3600) == [file("Klax (USA).pdf")])

        var changed = folder
        changed.modified = "10-22-26  09:00AM"
        #expect(cache.entries(of: path, folder: changed, now: read + 3600) == nil)
        #expect(cache.entries(of: path, folder: folder, now: read + 31 * 24 * 3600) == nil)
    }

    private func file(_ name: String, _ size: Int64 = 100) -> EmuMovies.Entry { .init(name: name, isFolder: false, size: size) }

    @Test func groupsPacksAndTheirParts() {
        let packs = EmuMovies.packs(in: [
            file("Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1).part2.rar", 50),
            file("Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1).part1.rar", 500),
            file("Super Nintendo Entertainment System (Boxes-Back)(No-Intro)(EM 2.1).zip"),
            file("Super Nintendo (2D Carts)(Kondorito 1.0).zip"),
            file("Super Nintendo Entertainment System (Logos)(No-Intro)(EM 2.2).zip"),
            file("Super Nintendo (3D Boxes-Alt1)(No-Intro_HyperBase)(EM 20151001).7z"),
            file("readme.txt")
        ])
        #expect(packs.map(\.kind) == [.physicalMedia, .boxes3D, .covers, .logos])
        #expect(EmuMovies.kind(ofPack: "Nintendo NES (2D Cartridges-Shaded)(EM 1.1)") == .physicalMedia)
        #expect(EmuMovies.kind(ofPack: "NEC PC Engine - Turbografx 16 (2D Carts)(No-Intro 20200411)(EM 2.0)") == .physicalMedia)
        #expect(EmuMovies.kind(ofPack: "NEC PC Engine - Turbografx 16 (2D Carts-Labels)(No-Intro 20200411)(EM 2.0)") == nil)
        #expect(EmuMovies.kind(ofPack: "Sega Dreamcast (Discs)(SupraKarma 1.0)") == .physicalMedia)
        let covers = packs[2]
        #expect(covers.files == ["Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1).part1.rar",
                                 "Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1).part2.rar"])
        #expect(covers.size == 550)
        #expect(covers.isSplit)
    }

    @Test func picksEmuMoviesOwnNewestSet() {
        let packs = EmuMovies.packs(in: [
            file("Super Nintendo (2D Boxes-Accurate USA)(No-Intro)(32bit)(Jolu42 1.0.2).zip"),
            file("Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1).part1.rar"),
            file("Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1).part2.rar"),
            file("Super Nintendo (Gameplay Snaps)(No-Intro 20200617)(EM 1.2).rar"),
            file("Super Nintendo (Title Snaps)(No-Intro 20200617)(EM 1.2).rar"),
            file("Atari Lynx (Logos)(No-Intro)(EM 2.1).zip"),
            file("Atari Lynx (Logos)(No-Intro)(EM 1.0).zip")
        ])
        let best = EmuMovies.bestPacks(packs, canOpenSplit: true)
        #expect(best[.covers]?.name == "Super Nintendo Entertainment System (Boxes-2D)(No-Intro)(EM 2.1)")
        #expect(best[.screenshots]?.name == "Super Nintendo (Gameplay Snaps)(No-Intro 20200617)(EM 1.2)")
        #expect(best[.logos]?.name == "Atari Lynx (Logos)(No-Intro)(EM 2.1)")
        // Without a way to open split archives, the single one.
        #expect(EmuMovies.bestPacks(packs, canOpenSplit: false)[.covers]?.name == "Super Nintendo (2D Boxes-Accurate USA)(No-Intro)(32bit)(Jolu42 1.0.2)")
    }

    @Test func findsManualsAndVideos() {
        let folder = { (name: String) in EmuMovies.Entry(name: name, isFolder: true, size: 0) }
        let manuals = [folder("Sega 32X CD (Game Manuals)(EM 1.1)"), folder("Sega 32X (Game Manuals)(EM 20150125)"),
                       folder("Sony PlayStation (Game Manuals-Japan)(ReDump)(EM 1.4)"), folder("Sony PlayStation (Game Manuals)(ReDump)(EM 1.4)"),
                       folder("Sony PlayStation 2 (Game Manuals)(ReDump)(EM 2.1)"),
                       folder("Atari 2600 (Manuals)(CBZ)(No-Intro)(EM 2.1)"), folder("Atari 2600 (Manuals)(PDF)(No-Intro)(EM 2.1)")]
        #expect(EmuMovies.manualsFolder(in: manuals, prefix: "Sega 32X") == "Sega 32X (Game Manuals)(EM 20150125)")
        #expect(EmuMovies.manualsFolder(in: manuals, prefix: "Sony PlayStation") == "Sony PlayStation (Game Manuals)(ReDump)(EM 1.4)")
        #expect(EmuMovies.manualsFolder(in: manuals, prefix: "Atari 2600") == "Atari 2600 (Manuals)(PDF)(No-Intro)(EM 2.1)")

        let videos = [file("Atari Lynx - EM Default (4x3)(HQ).mp4"), file("Atari Lynx - Unified Alt (16x9)(HD).mp4"),
                      file("Atari Lynx - Unified (16x9)(HD).mp4"), file("Atari Lynx II - Unified (16x9)(HD).mp4")]
        #expect(EmuMovies.systemVideo(in: videos, prefix: "Atari Lynx")?.name == "Atari Lynx - Unified (16x9)(HD).mp4")
        #expect(EmuMovies.systemVideo(in: videos, prefix: "Atari Jaguar") == nil)

        let snaps = [folder("Nintendo Game Boy (Video Snaps-TKO Authentics)(HQ)(EM 2.2)"), folder("Nintendo Game Boy (Video Snaps)(HQ)(EM 2.6)"),
                     folder("Nintendo Game Boy Color (Video Snaps)(HQ)(EM 2.5)"),
                     folder("Nintendo Super Nintendo (Hacks & Homebrew)(Video Snaps)(HQ)(EM 1.5)"),
                     folder("Nintendo Super Nintendo (Video Snaps)(HQ)(HyperList)(EM 2.2)"),
                     folder("Nintendo Super Nintendo (Video Snaps)(HQ)(No-Intro 20210322)(EM 2.2)"),
                     folder("Nintendo Super Famicom (Video Snaps)(HQ)(HyperList)(EM 2.0)")]
        #expect(EmuMovies.videoSnapsFolders(in: snaps, prefixes: ["Nintendo Game Boy"]) == ["Nintendo Game Boy (Video Snaps)(HQ)(EM 2.6)"])
        #expect(EmuMovies.videoSnapsFolders(in: snaps, prefixes: EmuMovies.videoSnapsPrefixes(for: CanonicalSystemID(rawValue: "snes"))) == [
            "Nintendo Super Nintendo (Video Snaps)(HQ)(No-Intro 20210322)(EM 2.2)",
            "Nintendo Super Famicom (Video Snaps)(HQ)(HyperList)(EM 2.0)",
            "Nintendo Super Nintendo (Video Snaps)(HQ)(HyperList)(EM 2.2)"
        ])
    }

    @Test func matchesGamesToFilesByName() {
        let files = ["Klax (USA, Europe)", "A.P.B. - All Points Bulletin (USA, Europe)", "Gates of Zendocon, The (USA, Europe)",
                     "Rampage (USA, Europe)", "Rampage (Japan)", "Super Mario World 2 - Yoshi's Island (USA) (Rev 1)",
                     "Zelda - Link's Awakening (USA)", "Pit Fighter - The Ultimate Competition (USA, Europe)", "Wild Snake (USA)"]
        let games = ["Klax (USA, Europe)", "A.P.B. (USA, Europe)", "Gates of Zendocon (World)", "Rampage (World)",
                     "Super Mario World (USA)", "Zelda - Oracle of Ages (USA)", "Pit-Fighter (USA, Europe)", "WildSnake (USA)"]
        let matches = EmuMovies.match(games: games, files: files)
        #expect(matches["Klax (USA, Europe)"] == "Klax (USA, Europe)")
        #expect(matches["A.P.B. (USA, Europe)"] == "A.P.B. - All Points Bulletin (USA, Europe)")
        #expect(matches["Gates of Zendocon (World)"] == "Gates of Zendocon, The (USA, Europe)")
        #expect(matches["Rampage (World)"] == "Rampage (USA, Europe)")
        #expect(matches["Pit-Fighter (USA, Europe)"] == "Pit Fighter - The Ultimate Competition (USA, Europe)")
        #expect(matches["WildSnake (USA)"] == "Wild Snake (USA)")
        #expect(matches["Super Mario World (USA)"] == nil)
        #expect(matches["Zelda - Oracle of Ages (USA)"] == nil)
    }

    @Test func keepsTheLoginOffTheCommandLine() {
        let server = EmuMoviesServer(host: .usa, username: "me", password: #"p"a\ss"#)
        #expect(server.config() == #"user = "me:p\"a\\ss""# + "\n")
        #expect(server.url("/Official/Artwork/Nintendo Game & Watch/A #1 (USA).zip")
                == "ftp://files.emumovies.com/Official/Artwork/Nintendo%20Game%20&%20Watch/A%20%231%20(USA).zip")
    }

    @Test func everySystemHasANameSomewhere() {
        for system in ["snes", "atarilynx", "pcengine", "naomi2"] {
            let names = EmuMovies.names(for: .init(system))
            #expect(names?.artwork != nil)
        }
        #expect(EmuMovies.names(for: "snesh") == nil)
    }
}
