import Foundation
import Testing
@testable import RomsBoxLibraryScanning

struct ESDEMediaResolverTests {
    private let root: URL
    private let systemFolder: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "media-resolver-\(UUID().uuidString)")
        systemFolder = root.appending(path: "ROMs/triforce")
        try FileManager.default.createDirectory(at: systemFolder.appending(path: "images"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemFolder.appending(path: "videos"), withIntermediateDirectories: true)
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    private var resolver: ESDEMediaResolver {
        ESDEMediaResolver(esdeRoot: root, systemName: "triforce", systemFolder: systemFolder)
    }

    @Test func fallsBackToBatoceraStyleImagesInsideTheROMFolder() throws {
        // Real names from a Batocera triforce pack: box art preferred over
        // the screenshot ("-image") when both exist.
        try touch(systemFolder.appending(path: "images/Mario Kart Arcade GP (USA)-image.jpg"))
        try touch(systemFolder.appending(path: "images/Mario Kart Arcade GP (USA)-boxart.png"))
        #expect(resolver.resolveCoverArt(romNameNoExt: "Mario Kart Arcade GP (USA)")?.lastPathComponent == "Mario Kart Arcade GP (USA)-boxart.png")
    }

    @Test func downloadedMediaStillWinsOverInFolderImages() throws {
        try touch(systemFolder.appending(path: "images/F-Zero AX-boxart.png"))
        try touch(root.appending(path: "downloaded_media/triforce/covers/F-Zero AX.png"))
        #expect(resolver.resolveCoverArt(romNameNoExt: "F-Zero AX")?.path.contains("downloaded_media") == true)
    }

    @Test func findsInFolderVideos() throws {
        try touch(systemFolder.appending(path: "videos/F-Zero AX-video.mp4"))
        #expect(resolver.resolveVideo(romNameNoExt: "F-Zero AX")?.lastPathComponent == "F-Zero AX-video.mp4")
    }

    @Test func noMediaMeansNil() {
        #expect(resolver.resolveCoverArt(romNameNoExt: "Nothing Here") == nil)
    }
}
