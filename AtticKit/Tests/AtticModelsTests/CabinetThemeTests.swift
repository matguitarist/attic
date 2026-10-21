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
