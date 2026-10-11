import Foundation
import Testing
@testable import RomsBoxEmulation

struct RetroArchInstallationTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test func readsTildeSystemDirectoryFromConfig() {
        let config = """
        libretro_directory = "~/Library/Application Support/RetroArch/cores"
        system_directory = "~/Documents/RetroArch/system"
        """
        #expect(RetroArchInstallation.systemDirectoryURL(configContents: config).path == home.appending(path: "Documents/RetroArch/system").path)
    }

    @Test func readsAbsoluteSystemDirectory() {
        let url = RetroArchInstallation.systemDirectoryURL(configContents: "system_directory = \"/Volumes/Emu/BIOS\"")
        #expect(url.path == "/Volumes/Emu/BIOS")
    }

    @Test func fallsBackForDefaultOrMissing() {
        let fallback = home.appending(path: "Documents/RetroArch/system").path
        #expect(RetroArchInstallation.systemDirectoryURL(configContents: "system_directory = \"default\"").path == fallback)
        #expect(RetroArchInstallation.systemDirectoryURL(configContents: "video_driver = \"metal\"").path == fallback)
        #expect(RetroArchInstallation.systemDirectoryURL(configContents: nil).path == fallback)
    }
}
