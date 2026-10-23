import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// Renders SVG files, which ImageIO can't read, with WebKit.
///
/// The SVG is shown in an `<img>`, the way a browser shows an image, so its scripts and external files stay off.
/// WebKit turns it into a vector PDF, which is either the result or gets drawn into a bitmap at an exact size.
@MainActor
public enum SVGRenderer {
    public nonisolated static func isSVG(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .svg) ?? false
    }

    /// Renders the SVGs among `jobs`, so the rest can be converted like any other image.
    ///
    /// For PDF an SVG becomes a vector PDF, saved right away. For every other format it becomes a PNG in `scratch`.
    /// - Returns: The jobs left for `ImageConverter`, and what was already saved or failed.
    public static func render(
        _ jobs: [(source: ImageSource, directory: URL)],
        for format: ImageFormat,
        scratch: URL
    ) async -> (jobs: [(source: ImageSource, directory: URL)], result: ConversionResult) {
        var remaining: [(source: ImageSource, directory: URL)] = []
        var result = ConversionResult(outputs: [], failures: [], thumbnail: nil)
        for job in jobs {
            guard isSVG(job.source.url) else {
                remaining.append(job)
                continue
            }
            do {
                if format == .pdf {
                    let pdf = try await pdfData(of: job.source.url)
                    result.outputs.append(try OutputNaming.write(pdf, baseName: job.source.baseName, fileExtension: format.fileExtension, in: job.directory))
                    if result.thumbnail == nil {
                        result.thumbnail = rasterize(pdf, maxPixelSize: 160)
                    }
                } else {
                    var source = job.source
                    source.url = try await png(of: job.source.url, in: scratch)
                    remaining.append((source: source, directory: job.directory))
                }
            } catch {
                result.failures.append(error.localizedDescription)
            }
        }
        return (remaining, result)
    }

    /// A one-page vector PDF the size of the SVG.
    public static func pdfData(of url: URL) async throws -> Data {
        let unreadable = ConversionError.unreadableImage(url.lastPathComponent)
        guard let svg = try? Data(contentsOf: url) else { throw unreadable }
        let size = fitted(intrinsicSize(ofSVG: svg), maxLongEdge: 4096)

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
        // Keeps transparent areas transparent instead of white.
        webView.setValue(false, forKey: "drawsBackground")
        let loader = PageLoader()
        webView.navigationDelegate = loader
        let html = """
        <!doctype html><meta charset="utf-8">
        <style>html, body { margin: 0; background: transparent } img { display: block; width: \(size.width)px; height: \(size.height)px }</style>
        <img src="data:image/svg+xml;base64,\(svg.base64EncodedString())">
        """
        do {
            try await loader.load(html, in: webView)
            // Fails for an SVG WebKit can't parse, which would otherwise come out as an empty page.
            _ = try await webView.callAsyncJavaScript("await document.images[0].decode(); return true", arguments: [:], in: nil, in: .page)
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(origin: .zero, size: size)
            return try await withCheckedThrowingContinuation { continuation in
                webView.createPDF(configuration: configuration) { continuation.resume(with: $0) }
            }
        } catch {
            throw unreadable
        }
    }

    /// Renders the SVG as a PNG in `directory`, at twice its size and at least 1024 pixels on the long side.
    public static func png(of url: URL, in directory: URL) async throws -> URL {
        let pdf = try await pdfData(of: url)
        guard let image = rasterize(pdf) else { throw ConversionError.unreadableImage(url.lastPathComponent) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ConversionError.encodingFailed(.png)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodingFailed(.png) }
        return file
    }

    /// Draws the first page of a PDF into a bitmap, keeping transparency.
    /// Without `maxPixelSize` it uses the scale from `renderScale(forLongEdge:)`.
    nonisolated static func rasterize(_ pdf: Data, maxPixelSize: Int? = nil) -> CGImage? {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let page = CGPDFDocument(provider)?.page(at: 1)
        else {
            return nil
        }
        let box = page.getBoxRect(.mediaBox)
        let longEdge = max(box.width, box.height)
        guard longEdge > 0 else { return nil }
        let scale = maxPixelSize.map { CGFloat($0) / longEdge } ?? renderScale(forLongEdge: longEdge)
        let width = max(1, Int((box.width * scale).rounded()))
        let height = max(1, Int((box.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// Twice the size for sharp results on Retina screens, small icons scaled up to 1024 pixels, nothing over 8192.
    nonisolated static func renderScale(forLongEdge longEdge: CGFloat) -> CGFloat {
        min(max(2, 1024 / longEdge), 8192 / longEdge)
    }

    /// The size the SVG asks for, in CSS pixels, worked out the way browsers do from `width`, `height` and `viewBox`.
    nonisolated static func intrinsicSize(ofSVG data: Data) -> CGSize {
        let reader = RootElementReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        let attributes = reader.attributes

        let width = cssPixels(attributes["width"])
        let height = cssPixels(attributes["height"])
        let viewBox = attributes["viewBox"].flatMap { value -> CGSize? in
            let numbers = value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Double($0) }
            guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
            return CGSize(width: numbers[2], height: numbers[3])
        }
        switch (width, height, viewBox) {
        case let (width?, height?, _):
            return CGSize(width: width, height: height)
        case let (width?, nil, box?):
            return CGSize(width: width, height: width * box.height / box.width)
        case let (nil, height?, box?):
            return CGSize(width: height * box.width / box.height, height: height)
        case let (nil, nil, box?):
            return box
        default:
            // The browser default for an image without a size.
            return CGSize(width: width ?? 300, height: height ?? 150)
        }
    }

    /// An absolute SVG length in CSS pixels. Percentages and invalid values give nil.
    nonisolated static func cssPixels(_ value: String?) -> CGFloat? {
        guard var number = value?.trimmingCharacters(in: .whitespaces), !number.isEmpty else { return nil }
        let units: [(suffix: String, pixels: Double)] = [
            ("px", 1), ("pt", 4.0 / 3), ("pc", 16), ("mm", 96 / 25.4), ("cm", 96 / 2.54), ("in", 96), ("em", 16), ("ex", 8),
        ]
        var factor = 1.0
        if let unit = units.first(where: { number.hasSuffix($0.suffix) }) {
            number = String(number.dropLast(unit.suffix.count))
            factor = unit.pixels
        }
        guard let length = Double(number.trimmingCharacters(in: .whitespaces)), length.isFinite, length > 0 else { return nil }
        return CGFloat(length * factor)
    }

    private nonisolated static func fitted(_ size: CGSize, maxLongEdge: CGFloat) -> CGSize {
        let scale = min(1, maxLongEdge / max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Waits for a page to finish loading, giving up after a timeout.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView, timeout: Duration = .seconds(20)) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(URLError(.timedOut))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(URLError(.cancelled))
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

/// Reads the attributes of the outermost element and stops.
private final class RootElementReader: NSObject, XMLParserDelegate {
    private(set) var attributes: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        self.attributes = attributes
        parser.abortParsing()
    }
}
