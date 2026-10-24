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

    /// White on clear, in gray with transparency, as Steam's Hollow Knight
    /// logo is.
    private func grayPNGWithAlpha() throws -> Data {
        let (width, height) = (64, 32)
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for y in 8..<24 { for x in 8..<56 { bytes[(y * width + x) * 2] = 255; bytes[(y * width + x) * 2 + 1] = 255 } }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 16, bytesPerRow: width * 2,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func grayPicturesWithTransparencyStayVisibleAsHEIC() throws {
        // Big enough a PNG that the HEIC is smaller, so it's written.
        var png = try grayPNGWithAlpha()
        png.append(Data(count: 64_000))
        let heic = try #require(MediaFolder.heicData(from: png))
        let image = try #require(CGImageSourceCreateWithData(heic as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // The middle of the white bar, opaque and white.
        let middle = (16 * image.width + 32) * 4
        #expect(pixels[middle + 3] > 200)
        #expect(pixels[middle] > 200)
    }
}

