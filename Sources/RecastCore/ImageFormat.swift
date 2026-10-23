import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A format Recast can write.
public enum ImageFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case png, jpeg, heic, avif, tiff, gif, bmp, pdf

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .avif: "AVIF"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .pdf: "PDF"
        }
    }

    /// One word shown under the name in the format bar.
    public var caption: String {
        switch self {
        case .png: "Lossless"
        case .jpeg: "Universal"
        case .heic: "Compact"
        case .avif: "Modern"
        case .tiff: "Archival"
        case .gif: "Legacy"
        case .bmp: "Bitmap"
        case .pdf: "Document"
        }
    }

    /// A longer description for settings.
    public var summary: String {
        switch self {
        case .png: "Lossless and keeps transparency."
        case .jpeg: "Opens everywhere. Small files, no transparency."
        case .heic: "Apple's photo format. About half the size of JPEG."
        case .avif: "Modern web format with very small files."
        case .tiff: "Lossless, for print and archiving."
        case .gif: "Limited to 256 colors."
        case .bmp: "Uncompressed bitmap for older software."
        case .pdf: "A single-page document sized to the image."
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        default: rawValue
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .avif: UTType("public.avif") ?? .image
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        case .pdf: .pdf
        }
    }

    /// Lossy formats honour the quality setting.
    public var isLossy: Bool {
        [.jpeg, .heic, .avif].contains(self)
    }

    /// Formats without transparency get flattened onto white instead of black.
    public var supportsTransparency: Bool {
        ![.jpeg, .bmp].contains(self)
    }

    /// Whether this Mac can write the format. HEIC and AVIF encoding depend on the OS and hardware.
    public var isAvailable: Bool {
        self == .pdf || Self.encodableTypes.contains(utType.identifier)
    }

    public static let defaultSelection: Set<ImageFormat> = [.png, .jpeg, .heic, .avif, .tiff, .pdf]

    private static let encodableTypes = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
}
