import Foundation
import Testing
@testable import AtticEmulation

struct SteamLibraryTests {
    private let root: URL
    private let steam: URL
    private let roms: URL
    private let otherDrive: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "SteamLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        steam = root.appending(path: "Steam", directoryHint: .isDirectory)
        roms = root.appending(path: "ROMs", directoryHint: .isDirectory)
        otherDrive = root.appending(path: "Drive/SteamLibrary", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: steam.appending(path: "steamapps/common"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: roms.appending(path: "steam"), withIntermediateDirectories: true)
        try write(steam.appending(path: "steamapps/libraryfolders.vdf"), """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"\(steam.path)"
        \t\t"apps"
        \t\t{
        \t\t\t"367520"\t\t"5284750173"
        \t\t}
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"\(otherDrive.path)"
        \t\t"apps"
        \t\t{
        \t\t\t"413150"\t\t"711467377"
        \t\t}
        \t}
        }
        """)
    }

    private func write(_ url: URL, _ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// An app manifest and its install folder, with a Mac app in it or not.
    private func install(_ appID: String, _ name: String, flags: Int = 4, macApp: Bool = true, in library: URL? = nil) throws {
        let library = library ?? steam
        try write(library.appending(path: "steamapps/appmanifest_\(appID).acf"), """
        "AppState"
        {
        \t"appid"\t\t"\(appID)"
        \t"name"\t\t"\(name)"
        \t"StateFlags"\t\t"\(flags)"
        \t"installdir"\t\t"\(name)"
        }
        """)
        let folder = library.appending(path: "steamapps/common/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if macApp {
            try FileManager.default.createDirectory(at: folder.appending(path: "\(name).app/Contents"), withIntermediateDirectories: true)
        } else {
            try write(folder.appending(path: "\(name).exe"), "MZ")
        }
    }

    private var shortcuts: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: roms.appending(path: "steam").path)) ?? []).sorted()
    }

    @Test func listsOnlyInstalledGamesWithAMacApp() throws {
        try install("367520", "Hollow Knight")
        try install("228980", "Steamworks Common Redistributables", macApp: false)
        try install("1086940", "Baldurs Gate 3", flags: 1026) // still downloading
        try install("1569580", "Blue Prince", flags: 6) // installed, update queued
        let games = SteamLibrary.installedGames(steamFolder: steam)
        #expect(games.map(\.appID) == ["1569580", "367520"])
        #expect(games.first?.title == "Blue Prince")
    }

    @Test func anInstallFolderCanBeTheAppItself() throws {
        try install("413150", "Stardew Valley", macApp: false)
        try FileManager.default.createDirectory(at: steam.appending(path: "steamapps/common/Stardew Valley/Contents/MacOS"), withIntermediateDirectories: true)
        #expect(SteamLibrary.installedGames(steamFolder: steam).map(\.appID) == ["413150"])
    }

    @Test func findsGamesInOtherLibraries() throws {
        try FileManager.default.createDirectory(at: otherDrive.appending(path: "steamapps"), withIntermediateDirectories: true)
        try install("413150", "Stardew Valley", in: otherDrive)
        #expect(SteamLibrary.installedGames(steamFolder: steam).map(\.appID) == ["413150"])
    }

    @Test func shortcutsFollowWhatsInstalled() throws {
        try install("367520", "Hollow Knight")
        var result = SteamLibrary.syncShortcuts(romsRoots: [roms], steamFolder: steam)
        #expect(result.added == 1)
        #expect(shortcuts == ["Hollow Knight [367520].steam"])
        let shortcut = roms.appending(path: "steam/Hollow Knight [367520].steam")
        #expect(SteamLibrary.appID(shortcut: shortcut) == "367520")

        // Again: nothing to do.
        result = SteamLibrary.syncShortcuts(romsRoots: [roms], steamFolder: steam)
        #expect(result == (0, 0))

        // Uninstalled: its shortcut goes.
        try FileManager.default.removeItem(at: steam.appending(path: "steamapps/appmanifest_367520.acf"))
        result = SteamLibrary.syncShortcuts(romsRoots: [roms], steamFolder: steam)
        #expect(result.removed == 1)
        #expect(shortcuts.isEmpty)
    }

    @Test func keepsShortcutsOfGamesOnADisconnectedDrive() throws {
        // Stardew Valley's library drive isn't there.
        try write(roms.appending(path: "steam/Stardew Valley [413150].steam"), "413150")
        let result = SteamLibrary.syncShortcuts(romsRoots: [roms], steamFolder: steam)
        #expect(result.removed == 0)
        #expect(shortcuts == ["Stardew Valley [413150].steam"])
    }

    @Test func doesNothingWithoutASteamFolderInROMs() throws {
        try install("367520", "Hollow Knight")
        try FileManager.default.removeItem(at: roms.appending(path: "steam"))
        #expect(SteamLibrary.syncShortcuts(romsRoots: [roms], steamFolder: steam) == (0, 0))
    }

    @Test func readsTheAppIDFromTheNameWhenTheFileIsEmpty() throws {
        let shortcut = roms.appending(path: "steam/Celeste [504230].steam")
        try write(shortcut, "")
        #expect(SteamLibrary.appID(shortcut: shortcut) == "504230")
    }

    @Test func parsesKeyValuesWithEscapesAndComments() {
        let vdf = VDF.parse("""
        // a comment
        "AppState"
        {
            "name"  "Say \\"Hi\\""
            "NoQuotes" 12
            "Nested" { "a" "b" }
        }
        """)
        #expect(vdf["appstate"]?["name"]?.string == "Say \"Hi\"")
        #expect(vdf["AppState"]?["noquotes"]?.string == "12")
        #expect(vdf["AppState"]?["Nested"]?["a"]?.string == "b")
    }
}

struct SteamStoreTests {

    @Test func readsAppDetails() throws {
        let json = """
        {"3808690":{"success":true,"data":{
          "short_description":"You are a disease. Infect &amp; evolve.",
          "developers":["Aberrant Labs"],"publishers":["Slug Disco"],
          "genres":[{"id":"1","description":"Action"},{"id":"23","description":"Indie"}],
          "release_date":{"coming_soon":false,"date":"16 Jul, 2026"},
          "header_image":"https://example.com/header.jpg",
          "screenshots":[{"id":0,"path_full":"https://example.com/ss1.jpg"}]
        }}}
        """
        let info = try #require(SteamStore.details(from: Data(json.utf8), appID: "3808690"))
        #expect(info.description == "You are a disease. Infect & evolve.")
        #expect(info.developer == "Aberrant Labs")
        #expect(info.publisher == "Slug Disco")
        #expect(info.genre == "Action, Indie")
        #expect(info.coverURL?.absoluteString == "https://example.com/header.jpg")
        #expect(info.screenshotURL?.absoluteString == "https://example.com/ss1.jpg")
        let date = try #require(info.releaseDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 7, day: 16))
    }

    @Test func failedDetailsGiveNothing() {
        #expect(SteamStore.details(from: Data(#"{"1":{"success":false}}"#.utf8), appID: "1") == nil)
    }

    @Test func buildsAssetURLsFromTheirFormat() {
        let json = """
        {"response":{"store_items":[{"assets":{
          "asset_url_format":"steam/apps/3808690/${FILENAME}?t=1",
          "library_capsule":"aa/library_capsule.jpg","library_capsule_2x":"bb/library_capsule_2x.jpg",
          "library_hero":"cc/library_hero.jpg"
        }}]}}
        """
        let assets = SteamStore.assets(from: Data(json.utf8))
        #expect(assets.cover?.absoluteString == "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3808690/bb/library_capsule_2x.jpg?t=1")
        #expect(assets.hero?.absoluteString == "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/3808690/cc/library_hero.jpg?t=1")
        #expect(assets.logo == nil)
    }

    @Test func readsBothDateOrders() {
        #expect(SteamStore.releaseDate("Feb 24, 2017") != nil)
        #expect(SteamStore.releaseDate("24 Feb, 2017") != nil)
        #expect(SteamStore.releaseDate("Coming soon") == nil)
    }
}

struct SteamGridDBTests {

    @Test func takesTheFirstPicture() {
        let json = #"{"success":true,"data":[{"id":1,"url":"https://cdn2.steamgriddb.com/logo/a.png","score":3},{"id":2,"url":"https://cdn2.steamgriddb.com/logo/b.png"}]}"#
        #expect(SteamGridDB.firstURL(in: Data(json.utf8))?.lastPathComponent == "a.png")
    }

    @Test func nothingFoundOrRefusedGivesNothing() {
        #expect(SteamGridDB.firstURL(in: Data(#"{"success":true,"data":[]}"#.utf8)) == nil)
        #expect(SteamGridDB.firstURL(in: Data(#"{"success":false,"errors":["Authentication Required"]}"#.utf8)) == nil)
    }

    @Test func asksForPortraitCoversByAppID() {
        let url = SteamGridDB.requestURL(.cover, appID: "3808690").absoluteString
        #expect(url.hasPrefix("https://www.steamgriddb.com/api/v2/grids/steam/3808690?"))
        #expect(url.contains("dimensions=600x900"))
        #expect(!SteamGridDB.requestURL(.logo, appID: "1").absoluteString.contains("dimensions"))
    }
}
