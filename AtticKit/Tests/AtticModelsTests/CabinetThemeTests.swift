import Foundation
import Testing
@testable import AtticModels

struct CabinetThemeTests {
    @Test func colorsReadAndWriteHex() throws {
        let color = try #require(ThemeColor(hex: "#FF2E88"))
        #expect(color.red == 1)
        #expect(color.alpha == 1)
        #expect(color.hex == "#FF2E88")
        #expect(ThemeColor(hex: "1B2838E6")?.hex == "#1B2838E6")
        #expect(ThemeColor(hex: "#12345") == nil)
        #expect(ThemeColor(hex: "red") == nil)
    }

    @Test func builtInsRoundTrip() throws {
        for theme in CabinetTheme.builtIns {
            #expect(try CabinetTheme.decode(theme.encoded(), id: theme.id) == theme)
        }
    }

    @Test func aPartialThemeTakesTheRestFromItsBase() throws {
        let json = ##"{ "name": "Purple Arcade", "base": "arcade", "palette": { "accent": "#B04CFF" }, "tiles": { "showsTitles": false } }"##
        let theme = try CabinetTheme.decode(Data(json.utf8), id: "purple")
        #expect(theme.id == "purple")
        #expect(theme.name == "Purple Arcade")
        #expect(theme.layout == .wheel)
        #expect(theme.palette.accent.hex == "#B04CFF")
        #expect(theme.palette.text == CabinetTheme.arcade.palette.text)
        #expect(theme.tiles.showsTitles == false)
        #expect(theme.tiles.art == .logo)
    }

    @Test func aThemeOnAppleTVKeepsItsHeroAndFade() throws {
        let json = ##"{ "name": "Blue TV", "base": "apple-tv", "palette": { "accent": "#0A84FF" } }"##
        let theme = try CabinetTheme.decode(Data(json.utf8), id: "blue-tv")
        #expect(theme.layout == .hero)
        #expect(theme.backdrop.fade)
        #expect(theme.tiles.art == .fanart)
        #expect(theme.palette.accent.hex == "#0A84FF")
        #expect(CabinetTheme.showcase.backdrop.fade == false)
        #expect(theme.backdrop.playsVideo)
        #expect(CabinetTheme.showcase.backdrop.playsVideo == false)
    }

    @Test func withoutABaseItStartsFromShowcase() throws {
        let theme = try CabinetTheme.decode(Data(#"{ "name": "Mine", "layout": "grid" }"#.utf8), id: "mine")
        #expect(theme.layout == .grid)
        #expect(theme.palette == CabinetTheme.showcase.palette)
    }

    @Test func nullClearsABaseValue() throws {
        let json = #"{ "name": "Plain", "base": "big-picture", "typography": { "fontName": null } }"#
        let theme = try CabinetTheme.decode(Data(json.utf8), id: "plain")
        #expect(theme.typography.fontName == nil)
        #expect(theme.typography.titleSize == CabinetTheme.bigPicture.typography.titleSize)
    }

    @Test func aFullFileFromBeforeASettingExistedStillReads() throws {
        // Customize in 2.0.0 wrote every value, but there was no menu yet.
        var object = try #require(JSONSerialization.jsonObject(with: CabinetTheme.arcade.encoded()) as? [String: Any])
        object["menu"] = nil
        object["base"] = "arcade"
        let theme = try CabinetTheme.decode(JSONSerialization.data(withJSONObject: object), id: "old")
        #expect(theme.menu == CabinetTheme.arcade.menu)
    }

    @Test func adjustmentsReplaceOnlyWhatTheyName() throws {
        let theme = try CabinetTheme.arcade.applying(["palette": ["accent": "#3DDC84"], "tiles": ["art": "box3D"], "layout": "list"])
        #expect(theme.id == "arcade")
        #expect(theme.palette.accent.hex == "#3DDC84")
        #expect(theme.palette.background == CabinetTheme.arcade.palette.background)
        #expect(theme.tiles.art == .box3D)
        #expect(theme.tiles.focusScale == CabinetTheme.arcade.tiles.focusScale)
        #expect(theme.layout == .list)
        #expect(try CabinetTheme.arcade.applying([:]) == .arcade)
    }

    @Test func gameArtTakesACartridgeOrAMix() throws {
        for art in [CabinetTheme.Tiles.Art.medium, .mix] {
            let json = #"{ "name": "Mine", "base": "arcade", "tiles": { "art": "\#(art.rawValue)" } }"#
            let theme = try CabinetTheme.decode(Data(json.utf8), id: "mine")
            #expect(theme.tiles.art == art)
            #expect(try CabinetTheme.decode(theme.encoded(), id: "mine") == theme)
        }
        #expect(CabinetTheme.Tiles.Art.mix.usesBox3D && CabinetTheme.Tiles.Art.mix.usesMedium)
        #expect(CabinetTheme.Tiles.Art.medium.usesMedium && !CabinetTheme.Tiles.Art.medium.usesBox3D)
        #expect(!CabinetTheme.Tiles.Art.cover.usesMedium)
    }

    @Test func aThemeFromBeforeCartridgesStillReads() throws {
        // 2.10 themes name only the arts they had.
        for art in ["cover", "box3D", "screenshot", "logo", "fanart", "logoCard"] {
            let json = #"{ "name": "Old", "base": "showcase", "tiles": { "art": "\#(art)" } }"#
            #expect(try CabinetTheme.decode(Data(json.utf8), id: "old").tiles.art.rawValue == art)
        }
    }

    @Test func theMarqueeComesFromTheTheme() throws {
        #expect(CabinetTheme.arcade.marquee == CabinetTheme.Marquee())
        #expect(CabinetTheme.arcade.marquee.fit == .fit)
        #expect(CabinetTheme.arcade.marquee.background.hex == "#000000")
        let json = ##"{ "name": "Lit", "base": "arcade", "marquee": { "fit": "fill", "background": "#1B2838" } }"##
        let theme = try CabinetTheme.decode(Data(json.utf8), id: "lit")
        #expect(theme.marquee.fit == .fill)
        #expect(theme.marquee.background.hex == "#1B2838")
        #expect(try CabinetTheme.decode(theme.encoded(), id: "lit") == theme)
        // Only one of the two: the other from the base.
        let half = try CabinetTheme.decode(Data(#"{ "name": "Half", "marquee": { "fit": "fill" } }"#.utf8), id: "half")
        #expect(half.marquee.background == CabinetTheme.showcase.marquee.background)
        // A file written before there was a marquee.
        var object = try #require(JSONSerialization.jsonObject(with: CabinetTheme.upright.encoded()) as? [String: Any])
        object["marquee"] = nil
        object["base"] = "upright"
        #expect(try CabinetTheme.decode(JSONSerialization.data(withJSONObject: object), id: "old").marquee == CabinetTheme.Marquee())
    }

    @Test func theMarqueeShowsTheBestThereIs() {
        typealias Content = CabinetTheme.Marquee.Content
        #expect(Content.resolve(hasGame: true, hasMarquee: true, hasLogo: true, sectionHasLogo: true) == .gameMarquee)
        #expect(Content.resolve(hasGame: true, hasMarquee: false, hasLogo: true, sectionHasLogo: true) == .gameLogo)
        #expect(Content.resolve(hasGame: true, hasMarquee: false, hasLogo: false, sectionHasLogo: true) == .gameTitle)
        #expect(Content.resolve(hasGame: false, hasMarquee: true, hasLogo: true, sectionHasLogo: true) == .sectionLogo)
        #expect(Content.resolve(hasGame: false, hasMarquee: false, hasLogo: false, sectionHasLogo: false) == .sectionTitle)
    }

    @Test func badValuesAreErrors() {
        #expect(throws: (any Error).self) {
            try CabinetTheme.decode(Data(#"{ "palette": { "accent": "pink" } }"#.utf8), id: "bad")
        }
        #expect(throws: (any Error).self) {
            try CabinetTheme.decode(Data(#"{ "layout": "spiral" }"#.utf8), id: "bad")
        }
        #expect(throws: (any Error).self) {
            try CabinetTheme.decode(Data("[]".utf8), id: "bad")
        }
    }
}
