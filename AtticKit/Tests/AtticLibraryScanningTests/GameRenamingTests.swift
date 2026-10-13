import Foundation
import Testing
@testable import AtticLibraryScanning

@Suite("Renaming a game")
struct GameRenamingTests {
    private let root: URL
    private let system: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "GameRenamingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        system = root.appending(path: "ROMs/snes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
    }

    private func write(_ path: String, _ text: String = "x") throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path)
    }

    @Test func takesMediaGamelistAndSavesAlong() throws {
        let rom = try write("ROMs/snes/Wild Snake (USA).sfc")
        _ = try write("Media/snes/covers/Wild Snake (USA).heic")
        _ = try write("Media/snes/manuals/Wild Snake (USA).pdf")
        _ = try write("Media/snes/covers/Wild Snake (USA) (Beta).heic")
        _ = try write("Gamelists/snes/gamelist.xml", "<gameList><game><path>./Wild Snake (USA).sfc</path><name>Wild Snake</name></game></gameList>")
        _ = try write("Saves/snes/Wild Snake (USA).srm")
        _ = try write("States/snes/Wild Snake (USA).state1")
        let saveFolders = [root.appending(path: "Saves/snes"), root.appending(path: "States/snes")]

        let moved = GameRenaming.rename(rom, to: "WildSnake (USA)", systemFolder: system, saveFolders: saveFolders)

        #expect(moved?.to.lastPathComponent == "WildSnake (USA).sfc")
        #expect(exists("ROMs/snes/WildSnake (USA).sfc") && !exists("ROMs/snes/Wild Snake (USA).sfc"))
        #expect(exists("Media/snes/covers/WildSnake (USA).heic"))
        #expect(exists("Media/snes/manuals/WildSnake (USA).pdf"))
        // Another game's media stays.
        #expect(exists("Media/snes/covers/Wild Snake (USA) (Beta).heic"))
        let cover = root.appending(path: "Media/snes/covers/Wild Snake (USA).heic").resolvingSymlinksInPath().path
        #expect(moved?.media[cover] == root.appending(path: "Media/snes/covers/WildSnake (USA).heic").resolvingSymlinksInPath().path)
        #expect(exists("Saves/snes/WildSnake (USA).srm"))
        #expect(exists("States/snes/WildSnake (USA).state1"))
        let gamelist = try String(contentsOf: root.appending(path: "Gamelists/snes/gamelist.xml"), encoding: .utf8)
        #expect(gamelist.contains("<path>./WildSnake (USA).sfc</path>"))
    }

    @Test func aZippedGamesSavesStay() throws {
        let rom = try write("ROMs/snes/Wild Snake (USA).zip")
        _ = try write("Saves/snes/Wild Snake (USA).srm")
        let moved = GameRenaming.rename(rom, to: "WildSnake (USA)", systemFolder: system, saveFolders: [root.appending(path: "Saves/snes")])
        #expect(moved != nil)
        #expect(exists("Saves/snes/Wild Snake (USA).srm"))
    }

    @Test func aChangeOfCaseOnly() throws {
        let rom = try write("ROMs/snes/Save our Ship (USA).zip")
        let moved = GameRenaming.rename(rom, to: "Save Our Ship (USA)", systemFolder: system, saveFolders: [])
        #expect(moved != nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: system.path)
        #expect(names == ["Save Our Ship (USA).zip"])
    }

    @Test func neverOverwritesAnotherFile() throws {
        let rom = try write("ROMs/snes/A.zip", "a")
        _ = try write("ROMs/snes/B.zip", "b")
        #expect(GameRenaming.rename(rom, to: "B", systemFolder: system, saveFolders: []) == nil)
        #expect(exists("ROMs/snes/A.zip"))
        #expect(try String(contentsOf: system.appending(path: "B.zip"), encoding: .utf8) == "b")
    }

    @Test func aSlashInANameIsntAFolder() {
        #expect(GameRenaming.fileStem("AC/DC: Live") == "AC-DC - Live")
    }
}
