import AppKit
import RecastCore

struct ConversionSummary {
    var format: ImageFormat
    var outputs: [URL]
    var failures: [String]
    var thumbnail: NSImage?

    var title: String {
        switch outputs.count {
        case 0: "Couldn't convert"
        case 1: outputs[0].lastPathComponent
        default: "\(outputs.count) images converted to \(format.displayName)"
        }
    }

    var subtitle: String {
        if outputs.isEmpty {
            return failures.first ?? "There's no image in what you dropped."
        }
        if !failures.isEmpty {
            return "\(failures.count) couldn't be converted"
        }
        let folders = Set(outputs.map { $0.deletingLastPathComponent().standardizedFileURL })
        guard folders.count == 1, let folder = folders.first else { return "Saved next to the originals" }
        return "Saved to \(FileManager.default.displayName(atPath: folder.path))"
    }
}

/// Runs conversions with the user's settings and does the follow-up actions.
@MainActor
final class ConversionService {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func run(_ intake: ImageIntake, to format: ImageFormat) async -> ConversionSummary {
        defer { intake.cleanUp() }

        let sources = await intake.resolve(allowDownloads: settings.fetchLinkedImages)
        guard !sources.isEmpty else {
            return ConversionSummary(format: format, outputs: [], failures: ["There's no image in what you dropped."])
        }

        let jobs = sources.map { (source: $0, directory: settings.outputFolder(forOriginalIn: $0.originalFolder)) }
        let options = settings.conversionOptions
        let result = await Task.detached(priority: .userInitiated) {
            ImageConverter.convert(jobs, to: format, options: options)
        }.value

        if !result.outputs.isEmpty {
            finish(result.outputs, format: format)
        }
        return ConversionSummary(
            format: format,
            outputs: result.outputs,
            failures: result.failures,
            thumbnail: result.thumbnail.map { NSImage(cgImage: $0, size: .zero) }
        )
    }

    private func finish(_ outputs: [URL], format: ImageFormat) {
        if settings.copyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let items = outputs.map { url in
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                // Image data too, so apps that only paste pictures (chat, design tools) get it.
                if let data = try? Data(contentsOf: url) {
                    item.setData(data, forType: NSPasteboard.PasteboardType(format.utType.identifier))
                }
                return item
            }
            pasteboard.writeObjects(items)
        }
        if settings.revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }
}
