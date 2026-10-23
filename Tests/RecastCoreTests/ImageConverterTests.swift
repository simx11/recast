import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import RecastCore

struct ImageConverterTests {
    let directory = Fixture.makeDirectory()

    @Test(arguments: ImageFormat.allCases.filter(\.isAvailable))
    func convertsToEveryAvailableFormat(_ format: ImageFormat) throws {
        let png = Fixture.write(Fixture.image(transparent: true), as: .png, to: directory.appendingPathComponent("source.png"))

        let outputDirectory = Fixture.makeDirectory()

        let output = try ImageConverter.convert(png, to: format, in: outputDirectory)

        #expect(output.lastPathComponent == "source.\(format.fileExtension)")
        if format == .pdf {
            let data = try Data(contentsOf: output)
            #expect(data.starts(with: Data("%PDF".utf8)))
        } else {
            let result = Fixture.source(output)
            #expect(result.type == format.utType.identifier)
            #expect(result.width == 40)
            #expect(result.height == 30)
        }
    }

    @Test func heicConvertsToJPEGAndPNG() throws {
        try #require(ImageFormat.heic.isAvailable)
        let heic = Fixture.write(Fixture.image(), as: .heic, to: directory.appendingPathComponent("IMG_0001.heic"))

        let jpeg = try ImageConverter.convert(heic, to: .jpeg, in: directory)
        let png = try ImageConverter.convert(heic, to: .png, in: directory)

        #expect(jpeg.lastPathComponent == "IMG_0001.jpg")
        #expect(Fixture.source(jpeg).type == UTType.jpeg.identifier)
        #expect(Fixture.source(png).type == UTType.png.identifier)
    }

    @Test func flattensTransparencyOntoWhite() throws {
        let png = Fixture.write(Fixture.image(transparent: true), as: .png, to: directory.appendingPathComponent("logo.png"))

        let jpeg = try ImageConverter.convert(png, to: .jpeg, in: directory, options: .init(quality: 1))

        // Top right was transparent; JPEG would otherwise turn it black.
        let pixel = Fixture.pixel(in: jpeg, x: 35, y: 2)
        #expect(pixel[0] > 245 && pixel[1] > 245 && pixel[2] > 245)
    }

    @Test func appliesOrientationToPixels() throws {
        let rotated = Fixture.write(
            Fixture.image(width: 40, height: 20),
            as: .jpeg,
            to: directory.appendingPathComponent("rotated.jpg"),
            properties: [kCGImagePropertyOrientation: 6]
        )

        let png = try ImageConverter.convert(rotated, to: .png, in: directory)

        let result = Fixture.source(png)
        #expect(result.width == 20)
        #expect(result.height == 40)
        #expect((result.properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test(arguments: [true, false])
    func keepsOrStripsLocation(keepMetadata: Bool) throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N"]
        let jpeg = Fixture.write(
            Fixture.image(),
            as: .jpeg,
            to: directory.appendingPathComponent("trip.jpg"),
            properties: [kCGImagePropertyGPSDictionary: gps]
        )

        let output = try ImageConverter.convert(jpeg, to: .png, in: directory, options: .init(keepMetadata: keepMetadata))

        let hasGPS = Fixture.source(output).properties[kCGImagePropertyGPSDictionary] != nil
        #expect(hasGPS == keepMetadata)
    }

    @Test func neverOverwritesExistingFiles() throws {
        let png = Fixture.write(Fixture.image(), as: .png, to: directory.appendingPathComponent("photo.png"))

        let first = try ImageConverter.convert(png, to: .jpeg, in: directory)
        let second = try ImageConverter.convert(png, to: .jpeg, in: directory)
        let sameFormat = try ImageConverter.convert(png, to: .png, in: directory)

        #expect(first.lastPathComponent == "photo.jpg")
        #expect(second.lastPathComponent == "photo 2.jpg")
        #expect(sameFormat.lastPathComponent == "photo 2.png")
    }

    @Test func pdfPageMatchesImageDPI() throws {
        let png = Fixture.write(
            Fixture.image(width: 288, height: 144),
            as: .png,
            to: directory.appendingPathComponent("scan.png"),
            properties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]
        )

        let pdf = try ImageConverter.convert(png, to: .pdf, in: directory)

        let page = try #require(CGPDFDocument(pdf as CFURL)?.page(at: 1))
        #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 144, height: 72))
    }

    @Test func rejectsFilesThatArentImages() throws {
        let text = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)

        #expect(throws: ConversionError.unreadableImage("notes.txt")) {
            try ImageConverter.convert(text, to: .png, in: directory)
        }
    }

    @Test func batchCollectsFailuresAndThumbnail() throws {
        let png = Fixture.write(Fixture.image(), as: .png, to: directory.appendingPathComponent("a.png"))
        let text = directory.appendingPathComponent("b.txt")
        try Data("nope".utf8).write(to: text)

        let result = ImageConverter.convert(
            [
                (ImageSource(url: png, baseName: "a"), directory),
                (ImageSource(url: text, baseName: "b"), directory),
            ],
            to: .jpeg,
            options: .init()
        )

        #expect(result.outputs.map(\.lastPathComponent) == ["a.jpg"])
        #expect(result.failures.count == 1)
        #expect(result.thumbnail != nil)
    }

    @Test func sanitizesNames() {
        #expect(OutputNaming.sanitized("a/b:c") == "a-b-c")
        #expect(OutputNaming.sanitized("..hidden") == "hidden")
        #expect(OutputNaming.sanitized("   ") == "Image")
    }
}
