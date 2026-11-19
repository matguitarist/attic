import Foundation
import Testing
@testable import AtticEmulation

struct Namco2x6Tests {
    private let pages = Data((0..<(Namco2x6.pageCount * 512)).map { UInt8($0 % 251) })
    private let spare = Data((0..<(Namco2x6.pageCount * 16)).map { UInt8($0 % 13) })

    @Test func cardPutsEachPageBeforeItsSpareBytes() {
        let card = Namco2x6.interleave(pages: pages, spare: spare)
        #expect(card.count == Namco2x6.cardSize)
        #expect(card[0..<512] == pages[0..<512])
        #expect(card[512..<528] == spare[0..<16])
        #expect(card[528..<1040] == pages[512..<1024])
        #expect(card[(card.count - 16)...] == spare[(spare.count - 16)...])
    }

    @Test func cardIsMadeFromMAMEsTwoFiles() {
        let files = ["sc23vera.ic002": pages, "sc23vera_spr.ic002": spare]
        let card = Namco2x6.card(names: files.mapValues(\.count)) { files[$0] }
        #expect(card == Namco2x6.interleave(pages: pages, spare: spare))
    }

    @Test func aWholeCardIsTakenAsItIs() {
        let whole = Data(repeating: 7, count: Namco2x6.cardSize)
        let files = ["dongle.bin": whole]
        #expect(Namco2x6.card(names: files.mapValues(\.count)) { files[$0] } == whole)
    }

    @Test func filesInAFolderOfTheZipAreLeftOut() {
        let files = ["tekken4c/tef1verc.ic002": pages, "tekken4c/tef3verc_spr.ic002": spare]
        #expect(Namco2x6.card(names: files.mapValues(\.count)) { files[$0] } == nil)
    }

    @Test func clonesFindTheirParentsMedia() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let parentFolder = root.appending(path: "tekken4", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parentFolder, withIntermediateDirectories: true)
        try Data().write(to: parentFolder.appending(path: "tef1dvd0.chd"))

        #expect(Namco2x6.media(forSet: root.appending(path: "tekken4c.zip"))?.lastPathComponent == "tef1dvd0.chd")
        #expect(Namco2x6.media(forSet: root.appending(path: "tekken4.zip"))?.lastPathComponent == "tef1dvd0.chd")
        #expect(Namco2x6.media(forSet: root.appending(path: "soulclb2.zip")) == nil)
    }

    @Test func setsAreKnownByTheirNamcoID() {
        #expect(Namco2x6.game(forSet: URL(fileURLWithPath: "/roms/namco2x6/soulclb2.zip"))?.gameID == "NM00007")
        #expect(Namco2x6.game(forSet: URL(fileURLWithPath: "/roms/namco2x6/TimeCrs4j.zip")) == .init("NM00032", parent: "timecrs4"))
        // Every clone's parent is a set of the same game.
        for (_, game) in Namco2x6.games {
            if let parent = game.parent { #expect(Namco2x6.games[parent]?.gameID == game.gameID) }
        }
    }
}
