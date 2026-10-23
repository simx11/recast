import AppKit
import ImageIO
import UniformTypeIdentifiers

/// One image to convert, wherever it came from.
public struct ImageSource: Sendable {
    public var url: URL
    /// The name the converted file gets, without extension.
    public var baseName: String
    /// The folder of the original, when the user dragged a real file rather than something from a browser.
    public var originalFolder: URL?

    public init(url: URL, baseName: String, originalFolder: URL? = nil) {
        self.url = url
        self.baseName = baseName
        self.originalFolder = originalFolder
    }
}

/// Captures every image in a drop or on the clipboard.
///
/// Browsers rarely hand over a plain file. Chrome and Safari offer a file promise, raw image data or just a link,
/// and a drag's pasteboard is only readable during the drop, so the intake grabs what it can straight away
/// and turns it into files later in `resolve`.
public final class ImageIntake: @unchecked Sendable {
    /// Image data types, best first: originals before re-encoded TIFF.
    public static let imageDataTypes: [NSPasteboard.PasteboardType] = [
        "public.svg-image", "public.heic", "public.heif", "org.webmproject.webp", "public.avif", "public.png",
        "public.jpeg", "com.compuserve.gif", "public.tiff", "com.microsoft.bmp",
    ].map { NSPasteboard.PasteboardType($0) }

    /// Everything that might lead to an image.
    public static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL] + imageDataTypes + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    /// Cheap check that only looks at types, so nothing is read from the source app during a drag.
    public static func mightContainImages(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        !Set(types).isDisjoint(with: acceptedTypes)
    }

    /// Scratch space for promised, pasted and downloaded files. Removed by `cleanUp()`.
    public let workDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Recast-\(UUID().uuidString)", isDirectory: true)

    private let fileURLs: [URL]
    private let promises: PromiseCollector?
    private let imageData: (data: Data, type: UTType)?
    private let link: URL?
    private let suggestedName: String

    public init(fileURLs: [URL]) {
        self.fileURLs = fileURLs
        promises = nil
        imageData = nil
        link = nil
        suggestedName = "Image"
    }

    /// Reads the pasteboard immediately. Call it while the drop is being performed.
    public init(pasteboard: NSPasteboard) {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        fileURLs = files
        guard files.isEmpty else {
            promises = nil
            imageData = nil
            link = nil
            suggestedName = "Image"
            return
        }

        let link = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { !$0.isFileURL }
        self.link = link
        suggestedName = link.flatMap(Self.name(fromLink:)) ?? "Image"

        // Promised files have to be requested while the drag source is still listening.
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        if receivers.isEmpty {
            promises = nil
        } else {
            try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            promises = PromiseCollector(receivers: receivers, destination: workDirectory)
        }

        imageData = Self.imageDataTypes.lazy.compactMap { type in
            pasteboard.data(forType: type).map { (data: $0, type: UTType(type.rawValue) ?? .image) }
        }.first
    }

    /// Turns the intake into image files on disk, waiting for promised files if needed.
    public func resolve(allowDownloads: Bool) async -> [ImageSource] {
        if !fileURLs.isEmpty {
            return fileURLs.map {
                ImageSource(url: $0, baseName: $0.deletingPathExtension().lastPathComponent, originalFolder: $0.deletingLastPathComponent())
            }
        }

        if let promises {
            let images = await promises.wait().filter(Self.isReadableImage)
            if !images.isEmpty {
                return images.map { ImageSource(url: $0, baseName: $0.deletingPathExtension().lastPathComponent) }
            }
        }

        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        if let imageData {
            let url = workDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(imageData.type.preferredFilenameExtension ?? "img")
            if (try? imageData.data.write(to: url)) != nil {
                return [ImageSource(url: url, baseName: suggestedName)]
            }
        }

        if allowDownloads, let link, let url = await Self.download(link, into: workDirectory) {
            return [ImageSource(url: url, baseName: suggestedName)]
        }
        return []
    }

    /// Deletes the scratch files. Never touches the user's own files.
    public func cleanUp() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    static func name(fromLink url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private static func isReadableImage(_ url: URL) -> Bool {
        SVGRenderer.isSVG(url) || CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(CGImageSourceGetType) != nil
    }

    /// Fetches the original image when a browser only provides its address. Also decodes `data:` URLs.
    private static func download(_ url: URL, into directory: URL) async -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "data"].contains(scheme),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
        else {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        let fileExtension = response.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "img"
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        guard (try? data.write(to: file)) != nil, isReadableImage(file) else { return nil }
        return file
    }
}

/// Receives promised files and lets callers await them, giving up after a timeout.
private final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = OperationQueue()
    private var urls: [URL] = []
    private var remaining = 0
    private var isFinished = false
    private var waiter: CheckedContinuation<[URL], Never>?

    init(receivers: [NSFilePromiseReceiver], destination: URL, timeout: TimeInterval = 20) {
        queue.qualityOfService = .userInitiated
        remaining = receivers.reduce(0) { $0 + max(1, $1.fileTypes.count) }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { [self] url, error in
                lock.withLock {
                    if error == nil {
                        urls.append(url)
                    }
                    remaining -= 1
                    if remaining <= 0 {
                        finish()
                    }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
            lock.withLock { finish() }
        }
    }

    func wait() async -> [URL] {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if isFinished {
                    continuation.resume(returning: urls)
                } else {
                    waiter = continuation
                }
            }
        }
    }

    /// Call with the lock held.
    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        waiter?.resume(returning: urls)
        waiter = nil
    }
}
