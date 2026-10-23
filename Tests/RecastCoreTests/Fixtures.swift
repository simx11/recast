import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Fixture {
    static func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RecastTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A gray image with a red bottom-left quadrant. With `transparent`, everything but the red is clear.
    static func image(width: Int = 40, height: Int = 30, transparent: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if transparent {
            context.clear(bounds)
        } else {
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(bounds)
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    @discardableResult
    static func write(_ image: CGImage, as type: UTType, to url: URL, properties: [CFString: Any] = [:]) -> URL {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return url
    }

    static func source(_ url: URL) -> (type: String?, width: Int, height: Int, properties: [CFString: Any]) {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return (
            CGImageSourceGetType(source) as String?,
            properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
            properties
        )
    }

    /// RGBA of one pixel, with (0, 0) at the top left.
    static func pixel(in url: URL, x: Int, y: Int) -> [UInt8] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel
    }
}
