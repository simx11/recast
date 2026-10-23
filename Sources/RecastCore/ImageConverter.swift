import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ConversionOptions: Sendable, Equatable {
    /// 0...1, used by lossy formats.
    public var quality: Double
    /// Keep camera, date and location metadata. Color profiles are always kept.
    public var keepMetadata: Bool

    public init(quality: Double = 0.85, keepMetadata: Bool = true) {
        self.quality = quality
        self.keepMetadata = keepMetadata
    }
}

public enum ConversionError: LocalizedError, Equatable {
    case unreadableImage(String)
    case formatUnavailable(ImageFormat)
    case encodingFailed(ImageFormat)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let name): "“\(name)” isn't an image Recast can read."
        case .formatUnavailable(let format): "This Mac can't write \(format.displayName) files."
        case .encodingFailed(let format): "Couldn't save the image as \(format.displayName)."
        }
    }
}

/// The result of converting a batch of images.
public struct ConversionResult: Sendable {
    public var outputs: [URL]
    /// Readable messages for the images that failed.
    public var failures: [String]
    /// A small preview of the first converted image.
    public var thumbnail: CGImage?
}

public enum ImageConverter {
    /// Converts the image at `source` and saves it in `directory`, never overwriting an existing file.
    /// - Returns: The new file.
    @discardableResult
    public static func convert(
        _ source: URL,
        to format: ImageFormat,
        in directory: URL,
        baseName: String? = nil,
        options: ConversionOptions = .init()
    ) throws -> URL {
        let data = try encode(source, as: format, options: options)
        let name = baseName ?? source.deletingPathExtension().lastPathComponent
        return try OutputNaming.write(data, baseName: name, fileExtension: format.fileExtension, in: directory)
    }

    /// Converts each source into the folder paired with it, collecting failures instead of stopping at the first.
    public static func convert(
        _ jobs: [(source: ImageSource, directory: URL)],
        to format: ImageFormat,
        options: ConversionOptions
    ) -> ConversionResult {
        var result = ConversionResult(outputs: [], failures: [], thumbnail: nil)
        for job in jobs {
            do {
                let output = try convert(job.source.url, to: format, in: job.directory, baseName: job.source.baseName, options: options)
                result.outputs.append(output)
                if result.thumbnail == nil {
                    result.thumbnail = thumbnail(of: job.source.url)
                }
            } catch {
                result.failures.append(error.localizedDescription)
            }
        }
        return result
    }

    /// Encodes the image at `source` as `format` and returns the file's bytes.
    public static func encode(_ source: URL, as format: ImageFormat, options: ConversionOptions = .init()) throws -> Data {
        guard format.isAvailable else { throw ConversionError.formatUnavailable(format) }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(imageSource) > 0
        else {
            throw ConversionError.unreadableImage(source.lastPathComponent)
        }

        // HEIC files can hold several images (bursts, depth maps); the primary one is the photo.
        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] ?? [:]
        guard var image = orientedImage(from: imageSource, at: index, properties: properties) else {
            throw ConversionError.unreadableImage(source.lastPathComponent)
        }
        if !format.supportsTransparency, image.hasAlpha {
            image = try flattened(image, for: format)
        }

        if format == .pdf {
            return try pdfData(for: image, properties: properties)
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utType.identifier as CFString, 1, nil) else {
            throw ConversionError.formatUnavailable(format)
        }
        var outputProperties = options.keepMetadata ? metadata(from: properties, for: image) : [:]
        if format.isLossy {
            outputProperties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodingFailed(format) }
        return output as Data
    }

    /// A small preview, or nil if ImageIO can't read the file.
    public static func thumbnail(of url: URL, maxPixelSize: Int = 160) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), options as CFDictionary)
    }

    /// Returns the image with its EXIF orientation applied to the pixels, so every app shows it the right way up.
    private static func orientedImage(from source: CGImageSource, at index: Int, properties: [CFString: Any]) -> CGImage? {
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard orientation != 1,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return CGImageSourceCreateImageAtIndex(source, index, nil)
        }
        // The thumbnail API applies the orientation for us; asking for the full size keeps every pixel.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private static func flattened(_ image: CGImage, for format: ImageFormat) throws -> CGImage {
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ConversionError.encodingFailed(format)
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let result = context.makeImage() else { throw ConversionError.encodingFailed(format) }
        return result
    }

    /// The metadata worth carrying over. Orientation is reset because the pixels are already upright.
    private static func metadata(from properties: [CFString: Any], for image: CGImage) -> [CFString: Any] {
        let keys = [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyDPIWidth,
            kCGImagePropertyDPIHeight,
        ]
        var result: [CFString: Any] = [:]
        for key in keys {
            result[key] = properties[key]
        }
        if var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            result[kCGImagePropertyExifDictionary] = exif
        }
        result[kCGImagePropertyOrientation] = 1
        return result
    }

    /// Sizes the page from the image's DPI so it prints at its intended size, like Preview does.
    private static func pdfData(for image: CGImage, properties: [CFString: Any]) throws -> Data {
        func points(_ pixels: Int, dpi: Any?) -> CGFloat {
            let dpi = (dpi as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
            return CGFloat(pixels) * 72 / dpi
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: points(image.width, dpi: properties[kCGImagePropertyDPIWidth]),
            height: points(image.height, dpi: properties[kCGImagePropertyDPIHeight])
        )
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ConversionError.encodingFailed(.pdf)
        }
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}
