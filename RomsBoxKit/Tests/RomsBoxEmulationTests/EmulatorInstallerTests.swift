import Foundation
import Testing
@testable import RomsBoxEmulation
@testable import RomsBoxModels

/// Serves pre-built local zip archives keyed by the URL the installer asks for.
private struct FixtureDownloader: FileDownloading {
    let archivesByURL: [URL: URL]

    func download(from url: URL) async throws -> URL {
        guard let archive = archivesByURL[url] else {
            throw EmulatorInstaller.InstallError.downloadFailed(url: url, statusCode: 404)
        }
        // The installer deletes what it downloads, so hand back a copy.
        let copy = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: archive, to: copy)
        return copy
    }
}

struct EmulatorInstallerTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "EmulatorInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var paths: EmulatorInstaller.Paths {
        EmulatorInstaller.Paths(
            coresDirectory: root.appending(path: "Cores"),
            coreInfoDirectory: root.appending(path: "CoreInfo"),
            applicationsDirectory: root.appending(path: "Applications")
        )
    }

    /// Zips `files` (relative path → contents) the way the real archives are
    /// laid out.
    private func makeZip(_ files: [String: String]) throws -> URL {
        let source = root.appending(path: "zip-src-\(UUID().uuidString)")
        for (relativePath, contents) in files {
            let file = source.appending(path: relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        let zip = root.appending(path: "\(UUID().uuidString).zip")
        try EmulatorInstaller.run("/usr/bin/ditto", ["-c", "-k", source.path, zip.path])
        return zip
    }

    @Test func installsCoreIntoOwnCoresDirectory() async throws {
        let zip = try makeZip(["snes9x_libretro.dylib": "fake dylib"])
        let installer = EmulatorInstaller(
            paths: paths,
            downloader: FixtureDownloader(archivesByURL: [EmulatorCatalog.coreDownloadURL(for: "snes9x_libretro"): zip])
        )

        let installed = try await installer.installCore("snes9x_libretro")

        #expect(installed == paths.coresDirectory.appending(path: "snes9x_libretro.dylib"))
        #expect(try String(contentsOf: installed, encoding: .utf8) == "fake dylib")
        #expect(installer.isCoreInstalled("snes9x_libretro"))
    }

    @Test func reinstallingACoreReplacesTheOldCopy() async throws {
        let first = try makeZip(["mgba_libretro.dylib": "v1"])
        let second = try makeZip(["mgba_libretro.dylib": "v2"])
        let url = EmulatorCatalog.coreDownloadURL(for: "mgba_libretro")

        try await EmulatorInstaller(paths: paths, downloader: FixtureDownloader(archivesByURL: [url: first])).installCore("mgba_libretro")
        let installed = try await EmulatorInstaller(paths: paths, downloader: FixtureDownloader(archivesByURL: [url: second])).installCore("mgba_libretro")

        #expect(try String(contentsOf: installed, encoding: .utf8) == "v2")
    }

    @Test func coreArchiveWithoutTheDylibFails() async throws {
        let zip = try makeZip(["readme.txt": "nothing here"])
        let installer = EmulatorInstaller(
            paths: paths,
            downloader: FixtureDownloader(archivesByURL: [EmulatorCatalog.coreDownloadURL(for: "mesen_libretro"): zip])
        )
        await #expect(throws: EmulatorInstaller.InstallError.missingFileInArchive("mesen_libretro.dylib")) {
            try await installer.installCore("mesen_libretro")
        }
        #expect(!installer.isCoreInstalled("mesen_libretro"))
    }

    @Test func installsAllInfoFiles() async throws {
        let zip = try makeZip([
            "snes9x_libretro.info": "display_name = \"Snes9x\"",
            "mgba_libretro.info": "display_name = \"mGBA\""
        ])
        let installer = EmulatorInstaller(
            paths: paths,
            downloader: FixtureDownloader(archivesByURL: [EmulatorCatalog.coreInfoArchiveURL: zip])
        )

        try await installer.installCoreInfoFiles()

        let installed = try FileManager.default.contentsOfDirectory(atPath: paths.coreInfoDirectory.path).sorted()
        #expect(installed == ["mgba_libretro.info", "snes9x_libretro.info"])
    }

    @Test func installsStandaloneAppBundle() async throws {
        let emulator = EmulatorCatalog.duckStation
        let zip = try makeZip(["DuckStation.app/Contents/MacOS/DuckStation": "binary"])
        let installer = EmulatorInstaller(
            paths: paths,
            downloader: FixtureDownloader(archivesByURL: [emulator.downloadURL: zip])
        )

        let app = try await installer.installStandalone(emulator)

        #expect(app == paths.applicationsDirectory.appending(path: "DuckStation/DuckStation.app"))
        #expect(installer.installedAppURL(for: emulator) == app)
    }

    @Test func picksHighestStableRetroArchVersion() {
        let html = """
        <a href="/stable/1.9.14/">1.9.14</a>
        <a href="/stable/1.22.2/">1.22.2</a>
        <a href="/stable/1.22.10/">1.22.10</a>
        <a href="/stable/1.3.6/">1.3.6</a>
        """
        #expect(EmulatorInstaller.latestStableVersion(inBuildbotIndex: html) == "1.22.10")
        #expect(EmulatorInstaller.latestStableVersion(inBuildbotIndex: "nothing") == nil)
    }
}

struct DolphinReleaseFeedTests {
    @Test func picksTheMacOSDiskImage() {
        let json = """
        {"shortrev": "2609a", "artifacts": [
          {"system": "Linux x86_64 (Flatpak)", "url": "https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-x86_64.flatpak"},
          {"system": "macOS (ARM/Intel Universal)", "url": "https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-universal.dmg"},
          {"system": "Windows x64", "url": "https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-x64.7z"}
        ]}
        """
        #expect(EmulatorInstaller.macOSDiskImageURL(inDolphinReleaseFeed: Data(json.utf8))?.absoluteString
            == "https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-universal.dmg")
        #expect(EmulatorInstaller.macOSDiskImageURL(inDolphinReleaseFeed: Data("<html>".utf8)) == nil)
    }
}

struct EmulatorCatalogTests {
    @Test func everyTaxonomySystemHasAnEmulator() {
        for system in SystemTaxonomy.allSystems {
            let recommendation = EmulatorCatalog.recommendation(for: system.canonicalID)
            let hasEmulator = recommendation?.recommendedCore != nil || recommendation?.standalone.isEmpty == false
            #expect(hasEmulator, "No emulator for \(system.canonicalID.rawValue)")
        }
    }

    @Test func coreIdentifiersUseLibretroNaming() {
        for recommendation in EmulatorCatalog.recommendations {
            for core in recommendation.cores {
                #expect(core.coreIdentifier.hasSuffix("_libretro"), "\(core.coreIdentifier)")
            }
        }
    }

    @Test func multiSystemCoreMapsToEverySystemItServes() {
        let systems = Set(EmulatorCatalog.systems(forCore: "genesis_plus_gx_libretro"))
        #expect(systems == [.genesis, .mastersystem, .gamegear, .segacd])
    }

    @Test func preferredStandaloneSystemsActuallyHaveOne() {
        for recommendation in EmulatorCatalog.recommendations where recommendation.prefersStandalone {
            #expect(!recommendation.standalone.isEmpty, "\(recommendation.systemID.rawValue)")
        }
    }
}
