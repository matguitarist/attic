import Foundation
import Testing
@testable import AtticLibraryScanning

struct MetadataCheckTests {
    private func game(_ id: String, _ title: String, _ description: String?) -> MetadataCheck.Game {
        MetadataCheck.Game(id: id, title: title, romName: id, description: description)
    }

    /// Descriptions the Naomi GD-ROM scrape got wrong, and right.
    @Test func findsDescriptionsOfAnotherGame() {
        let doubts = MetadataCheck.doubts([
            game("vf4", "Virtua Fighter 4 Version C", "Grind Stormer is a 1993 vertically scrolling shooter arcade video game originally released by Toaplan."),
            game("kurucham", "Kurukuru Chameleon", "Kozure Ookami is a beat-'em-up based on the manga and film series."),
            game("ss2005", "Super Shanghai 2005", "Special Criminal Investigation is the sequel to the 1988 original Chase H.Q."),
            game("ikaruga", "Ikaruga", "Ikaruga (Japanese: 斑鳩) is a shoot 'em up developed by Treasure."),
            game("vf4evo", "Virtua Fighter 4: Evolution", "Evolution was an updated version of Virtua Fighter 4."),
            game("ggxxrl", "Guilty Gear XX #Reload", "Guilty Gear X2 #Reload (released as Guilty Gear XX: The Midnight Carnival #Reload) is a fighting game."),
            game("initd", "Initial D Arcade Stage", "In Initial D Arcade Stage, is an arcade racing game series."),
            game("tetkiwam", "Tetris Kiwamemichi", "The player controls a fleet of seven ships through three stages."),
            game("nothing", "Nothing Said", nil),
        ])
        #expect(doubts["vf4"] == .describesAnotherGame("Grind Stormer"))
        #expect(doubts["kurucham"] == .describesAnotherGame("Kozure Ookami"))
        #expect(doubts["ss2005"] == .describesAnotherGame("Special Criminal Investigation"))
        for good in ["ikaruga", "vf4evo", "ggxxrl", "initd", "tetkiwam", "nothing"] {
            #expect(doubts[good] == nil, "\(good)")
        }
    }

    /// What the first pass over a real library flagged wrongly.
    @Test func leavesOtherSpellingsAndSentencesAlone() {
        let doubts = MetadataCheck.doubts([
            game("fresman", "Fres Man", "Fresman is a PAC-MAN clone for two players."),
            game("starhawk", "Starhawk", "Star Hawk is a 3-D wireframe shoot-em-up."),
            game("clay", "ClayFighter", "Clay Fighter is a 2D fighting game."),
            game("hockey", "Hockey", "This game, as the name suggests, is a hockey simulation."),
            game("toki", "Toki", "The hero of the game is a young jungle-man named Toki."),
            game("puyo", "Puyo Puyo Tsuu", "A falling block game in which the goal is the combine four blocks."),
            game("ottifants", "Ottifants, The", "Bruno is a baby Ottifant. It's an ordinary evening."),
            game("gaia", "Illusion of Gaia", "Will is a young boy whose father disappeared long time ago."),
            game("xanagrams", "Xanagrams", "Xanagams is a single player educational word game."),
            game("squash", "Squash", "For many years this was the only squash game in existence."),
        ])
        #expect(doubts.isEmpty, "\(doubts)")
    }
}
