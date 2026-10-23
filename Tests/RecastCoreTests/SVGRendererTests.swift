import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import RecastCore

struct SVGRendererTests {
    let directory = Fixture.makeDirectory()

    /// The left half red, the right half clear.
    private func writeSVG(_ root: String = #"width="40" height="30""#, named name: String = "logo.svg") throws -> URL {
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" \(root) viewBox="0 0 40 30">
          <rect x="0" y="0" width="20" height="30" fill="#ff0000"/>
        </svg>
        """
        let url = directory.appendingPathComponent(name)
        try Data(svg.utf8).write(to: url)
        return url
    }

    @Test func readsTheSizeLikeBrowsersDo() {
        func size(_ attributes: String) -> CGSize {
            SVGRenderer.intrinsicSize(ofSVG: Data(#"<svg xmlns="http://www.w3.org/2000/svg" \#(attributes)/>"#.utf8))
        }
        #expect(size(#"width="40" height="30""#) == CGSize(width: 40, height: 30))
        #expect(size(#"width="1in" height="12pc""#) == CGSize(width: 96, height: 192))
        #expect(size(#"viewBox="0 0 24 12""#) == CGSize(width: 24, height: 12))
        #expect(size(#"width="48" viewBox="0,0,24,12""#) == CGSize(width: 48, height: 24))
        #expect(size(#"width="100%" height="100%" viewBox="0 0 24 12""#) == CGSize(width: 24, height: 12))
        #expect(size("") == CGSize(width: 300, height: 150))
    }

    @Test func rendersSmallIconsLargeAndLargeImagesAtTwiceTheirSize() {
        #expect(abs(SVGRenderer.renderScale(forLongEdge: 24) * 24 - 1024) < 0.001)
        #expect(SVGRenderer.renderScale(forLongEdge: 800) == 2)
        #expect(abs(SVGRenderer.renderScale(forLongEdge: 6000) * 6000 - 8192) < 0.001)
    }

    @Test func recognizesSVGFiles() {
        #expect(SVGRenderer.isSVG(URL(fileURLWithPath: "/tmp/logo.svg")))
        #expect(!SVGRenderer.isSVG(URL(fileURLWithPath: "/tmp/logo.png")))
    }

    @MainActor
    @Test func rendersToPNGKeepingTransparency() async throws {
        let png = try await SVGRenderer.png(of: try writeSVG(), in: directory)

        let result = Fixture.source(png)
        #expect(result.type == UTType.png.identifier)
        #expect(result.width == 1024)
        #expect(result.height == 768)
        let red = Fixture.pixel(in: png, x: 100, y: 384)
        #expect(red[0] > 240 && red[1] < 15 && red[2] < 15 && red[3] == 255)
        #expect(Fixture.pixel(in: png, x: 900, y: 384)[3] == 0)
    }

    @MainActor
    @Test func rendersToAVectorPDFTheSizeOfTheSVG() async throws {
        let source = ImageSource(url: try writeSVG(), baseName: "logo")
        let (jobs, result) = await SVGRenderer.render([(source: source, directory: directory)], for: .pdf, scratch: directory)

        #expect(jobs.isEmpty)
        #expect(result.failures.isEmpty)
        let pdf = try #require(result.outputs.first)
        #expect(pdf.lastPathComponent == "logo.pdf")
        let page = try #require(CGPDFDocument(pdf as CFURL)?.page(at: 1))
        #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 40, height: 30))
        #expect(result.thumbnail != nil)
    }

    @MainActor
    @Test func leavesOtherImagesAndReportsBrokenSVGs() async throws {
        let png = Fixture.write(Fixture.image(), as: .png, to: directory.appendingPathComponent("photo.png"))
        let broken = directory.appendingPathComponent("broken.svg")
        try Data("not an svg".utf8).write(to: broken)
        let jobs = [png, broken].map { (source: ImageSource(url: $0, baseName: "x"), directory: directory) }

        let (remaining, result) = await SVGRenderer.render(jobs, for: .jpeg, scratch: directory)

        #expect(remaining.map(\.source.url) == [png])
        #expect(result.failures == [ConversionError.unreadableImage("broken.svg").localizedDescription])
    }
}
