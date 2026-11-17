import Foundation
import Testing
@testable import AtticModels

struct CabinetThemeFolderTests {
    private func scratchFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AtticThemeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// Every value moved away from Showcase's, optional ones set.
    private func everythingChanged() throws -> CabinetTheme {
        var theme = CabinetTheme.showcase
        theme.name = "Mine: Night"
        theme.author = "Someone"
        theme.layout = .unboxed
        theme.palette.background = try #require(ThemeColor(hex: "#101820"))
        theme.palette.surface = try #require(ThemeColor(hex: "#20304080"))
        theme.palette.accent = try #require(ThemeColor(hex: "#FF2E88"))
        theme.palette.text = try #require(ThemeColor(hex: "#F0F0F0"))
        theme.palette.secondaryText = try #require(ThemeColor(hex: "#A0A0A0"))
        theme.palette.favorite = try #require(ThemeColor(hex: "#FFD60A"))
        theme.typography = .init(design: .serif, fontName: "Georgia", titleSize: 51, bodySize: 17, uppercase: true)
        theme.backdrop.source = .screenshot
        theme.backdrop.blur = 12
        theme.backdrop.dim = 0.35
        theme.backdrop.image = "back.png"
        theme.backdrop.fade = true
        theme.backdrop.playsVideo = true
        theme.tiles = .init(art: .mix, size: 0.4, spacing: 18, cornerRadius: 6, showsBackground: true, focusScale: 1.3,
                            unfocusedOpacity: 0.5, focusRing: true, focusGlow: true, showsTitles: false)
        theme.details.media = .box3D
        theme.details.playsVideo = false
        theme.details.showsLogo = false
        theme.details.titlePosition = .bottom
        theme.details.side = .trailing
        theme.details.showsMetadata = false
        theme.details.showsDescription = false
        theme.details.descriptionLines = 7
        theme.details.showsPhysicalMedia = false
        theme.details.showsArt = false
        theme.header = .init(showsLogos: false, showsClock: false, showsGameCount: false)
        theme.menu = .init(position: .trailing, width: 520, cornerRadius: 4, dim: 0.8)
        theme.systems.isEnabled = false
        theme.systems.showsStats = false
        theme.systems.playsVideo = false
        theme.systems.artFolder = "pictures"
        theme.systems.showsPicture = false
        theme.systems.style = .carousel
        theme.systems.band = try #require(ThemeColor(hex: "#303030"))
        theme.showsHints = false
        theme.marquee = .init(fit: .fill, background: try #require(ThemeColor(hex: "#202020")))
        return theme
    }

    @Test func aSavedThemeLoadsBackUnchanged() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        var theme = try everythingChanged()
        let folder = root.appending(path: "Night", directoryHint: .isDirectory)
        theme.id = "Night"
        try CabinetThemeFolder.save(theme, in: folder)
        #expect(try CabinetThemeFolder.load(folder) == theme)
    }

    @Test func savingAgainKeepsTheFolderPictures() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Night", directoryHint: .isDirectory)
        var theme = CabinetTheme.arcade
        theme.id = "Night"
        try CabinetThemeFolder.save(theme, in: folder)
        try Data([1, 2, 3]).write(to: folder.appending(path: "back.png"))
        theme.palette.accent = try #require(ThemeColor(hex: "#3DDC84"))
        try CabinetThemeFolder.save(theme, in: folder)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "back.png").path))
        #expect(try CabinetThemeFolder.load(folder).palette.accent.hex == "#3DDC84")
    }

    @Test func newFolderNamesAreSafeAndFree() {
        #expect(CabinetThemeFolder.newFolderName(for: "Night", taken: []) == "Night")
        #expect(CabinetThemeFolder.newFolderName(for: "Night", taken: ["night"]) == "Night 2")
        #expect(CabinetThemeFolder.newFolderName(for: "Night", taken: ["Night", "Night 2"]) == "Night 3")
        #expect(CabinetThemeFolder.newFolderName(for: "A/B: C", taken: []) == "A-B- C")
        #expect(CabinetThemeFolder.newFolderName(for: " ..", taken: []) == "Theme")
        #expect(CabinetThemeFolder.newFolderName(for: "Arcade", taken: Set(CabinetTheme.builtIns.map(\.id))) == "Arcade 2")
    }
}
