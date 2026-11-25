import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import AtticLibraryScanning

struct MediaHealthTests {
    /// A PNG `width` by `height`, opaque, or entirely clear.
    private func png(width: Int, height: Int, clear: Bool = false) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if !clear {
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func countsEachKindAndFindsWhatsWrong() throws {
        let emulation = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: emulation) }
        let nes = emulation.appending(path: "ROMs/nes", directoryHint: .isDirectory)
        let media = emulation.appending(path: "Media/nes", directoryHint: .isDirectory)
        func write(_ data: Data, _ path: String) throws {
            let url = media.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try write(png(width: 1000, height: 1400), "2dboxes/Good.png")
        try write(png(width: 200, height: 280), "2dboxes/Small.png")
        try write(png(width: 1000, height: 1400), "2dboxes/Unused.png")
        try write(png(width: 800, height: 300, clear: true), "logos/Good.png")
        try write(Data(), "screenshots/Good.png")
        try write(png(width: 256, height: 240), "screenshots/Small.png")

        let games = [
            MediaHealth.Game(title: "Good", system: .nes, systemFolder: nes, romRelativePath: "Good.nes",
                             coverPath: media.appending(path: "2dboxes/Good.png").path),
            MediaHealth.Game(title: "Small", system: .nes, systemFolder: nes, romRelativePath: "Small.nes",
                             coverPath: media.appending(path: "2dboxes/Small.png").path),
            // A screenshot for a cover, from before its box was there.
            MediaHealth.Game(title: "Unused", system: .nes, systemFolder: nes, romRelativePath: "Unused.nes",
                             coverPath: media.appending(path: "screenshots/Unused.png").path),
            MediaHealth.Game(title: "Bare", system: .nes, systemFolder: nes, romRelativePath: "Bare.nes", coverPath: nil),
        ]
        let (reports, cache) = MediaHealth.check(games)
        let report = try #require(reports.first)
        #expect(report.games == 4)
        #expect(report.have[.covers] == 3)
        #expect(report.missing(.covers) == 1)
        #expect(report.have[.screenshots] == 2)
        #expect(report.kinds.contains(.physicalMedia))
        #expect(!report.kinds.contains(.marquees))

        let found = Set(report.findings.map { "\($0.title) \($0.kind.rawValue) \($0.problem)" })
        #expect(found == [
            "Small 2dboxes small(width: 200, height: 280)",
            "Unused 2dboxes coverNotBox",
            "Good logos blank",
            "Good screenshots unreadable",
        ])

        // Checked again from the cache, the same; a file fixed since is
        // looked at again.
        #expect(Set(MediaHealth.check(games, cache: cache).reports[0].findings.map(\.id)) == Set(report.findings.map(\.id)))
        try write(png(width: 800, height: 300), "logos/Good.png")
        #expect(!MediaHealth.check(games, cache: cache).reports[0].findings.contains { $0.kind == .logos })
    }

    /// A found picture replaces a small one only when it's clearly larger,
    /// and a broken one whenever it shows something.
    @Test func aBetterPictureIsLargerOrReplacesABrokenOne() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let small = folder.appending(path: "small.png"), broken = folder.appending(path: "broken.png")
        try png(width: 150, height: 60).write(to: small)
        try Data().write(to: broken)

        #expect(MediaHealth.isBetter(try png(width: 600, height: 240), than: small, kind: .logos))
        #expect(!MediaHealth.isBetter(try png(width: 160, height: 64), than: small, kind: .logos))
        #expect(!MediaHealth.isBetter(try png(width: 600, height: 240, clear: true), than: small, kind: .logos))
        #expect(!MediaHealth.isBetter(Data("not a picture".utf8), than: small, kind: .logos))
        #expect(MediaHealth.isBetter(try png(width: 100, height: 40), than: broken, kind: .logos))
    }
}
