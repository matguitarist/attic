import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import AtticLibraryScanning

struct MediaQualityTests {

    private func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func readsAPicturesSize() throws {
        #expect(MediaQuality.size(ofImageData: try png(width: 320, height: 240)) == CGSize(width: 320, height: 240))
        #expect(MediaQuality.size(ofImageData: Data("not a picture".utf8)) == nil)
    }

    @Test func tellsLowQualityAndBetter() {
        #expect(MediaQuality.isLowQuality(image: CGSize(width: 640, height: 480), kind: .covers))
        #expect(!MediaQuality.isLowQuality(image: CGSize(width: 1000, height: 1400), kind: .covers))
        #expect(MediaQuality.isLowQuality(image: CGSize(width: 1400, height: 788), kind: .fanart))
        #expect(!MediaQuality.isLowQuality(image: CGSize(width: 1920, height: 1080), kind: .fanart))
        #expect(!MediaQuality.isLowQuality(image: CGSize(width: 800, height: 300), kind: .logos))
        #expect(!MediaQuality.isLowQuality(image: CGSize(width: 256, height: 224), kind: .screenshots))
        #expect(MediaQuality.isLowQuality(video: CGSize(width: 320, height: 240)))
        #expect(!MediaQuality.isLowQuality(video: CGSize(width: 640, height: 480)))
        #expect(MediaQuality.isBetter(CGSize(width: 1400, height: 1000), than: CGSize(width: 640, height: 480)))
        #expect(!MediaQuality.isBetter(CGSize(width: 660, height: 500), than: CGSize(width: 640, height: 480)))
    }
}
