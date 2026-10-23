import AppKit
import Testing
import UniformTypeIdentifiers
@testable import RecastCore

struct ImageIntakeTests {
    let directory = Fixture.makeDirectory()

    private func withPasteboard(_ body: (NSPasteboard) async throws -> Void) async rethrows {
        let pasteboard = NSPasteboard(name: .init("RecastTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        try await body(pasteboard)
    }

    @Test func usesDraggedFilesInPlace() async {
        let png = Fixture.write(Fixture.image(), as: .png, to: directory.appendingPathComponent("holiday.png"))

        await withPasteboard { pasteboard in
            pasteboard.writeObjects([png as NSURL])
            let sources = await ImageIntake(pasteboard: pasteboard).resolve(allowDownloads: false)

            #expect(sources.map(\.url) == [png])
            #expect(sources.first?.baseName == "holiday")
            #expect(sources.first?.originalFolder?.standardizedFileURL == directory.standardizedFileURL)
        }
    }

    @Test func savesImageDataNamedAfterItsLink() async throws {
        let png = Fixture.write(Fixture.image(), as: .png, to: directory.appendingPathComponent("x.png"))
        let data = try Data(contentsOf: png)

        await withPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            item.setString("https://example.com/cats/fluffy.webp?w=800", forType: .URL)
            pasteboard.writeObjects([item])

            let intake = ImageIntake(pasteboard: pasteboard)
            let sources = await intake.resolve(allowDownloads: false)

            #expect(sources.count == 1)
            #expect(sources.first?.baseName == "fluffy")
            #expect(sources.first?.originalFolder == nil)
            #expect(sources.first.map { Fixture.source($0.url).type } == UTType.png.identifier)

            intake.cleanUp()
            #expect(!FileManager.default.fileExists(atPath: intake.workDirectory.path))
        }
    }

    @Test func decodesDataURLsOnlyWhenAllowed() async throws {
        let png = Fixture.write(Fixture.image(), as: .png, to: directory.appendingPathComponent("y.png"))
        let link = "data:image/png;base64," + (try Data(contentsOf: png)).base64EncodedString()

        await withPasteboard { pasteboard in
            pasteboard.setString(link, forType: .URL)

            #expect(await ImageIntake(pasteboard: pasteboard).resolve(allowDownloads: false).isEmpty)
            let sources = await ImageIntake(pasteboard: pasteboard).resolve(allowDownloads: true)
            #expect(sources.count == 1)
            #expect(sources.first?.baseName == "Image")
        }
    }

    @Test func recognizesDragsWorthShowingTheBarFor() {
        #expect(ImageIntake.mightContainImages([.fileURL]))
        #expect(ImageIntake.mightContainImages([.init("public.jpeg")]))
        #expect(ImageIntake.mightContainImages([.init("com.apple.NSFilePromiseItemMetaData")]))
        #expect(!ImageIntake.mightContainImages([.string, .rtf]))
    }
}
