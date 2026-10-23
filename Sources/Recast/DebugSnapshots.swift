#if DEBUG
import AppKit
import RecastCore

/// Renders every window and format bar state to PNGs, and runs real drops through the format bar.
/// Lets you check layout without screen recording permission. Debug builds only:
///
///     scripts/build.sh debug && build/Recast.app/Contents/MacOS/Recast --snapshot /tmp/recast-snapshots
@MainActor
enum DebugSnapshots {
    static func runIfRequested(windows: WindowManager, overlay: OverlayController, settings: AppSettings) -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), flag + 1 < arguments.count else { return false }
        let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        Task {
            await run(in: folder, windows: windows, overlay: overlay, settings: settings)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func run(in folder: URL, windows: WindowManager, overlay: OverlayController, settings: AppSettings) async {
        windows.showWelcome()
        await pause()
        save(windows.welcomeWindow!, as: "welcome", in: folder)
        windows.welcomeWindow?.close()

        windows.showSettings()
        let tabs = windows.settingsWindow?.contentViewController as? NSTabViewController
        for (index, name) in ["settings-general", "settings-formats", "settings-about"].enumerated() {
            tabs?.selectedTabViewItemIndex = index
            await pause()
            save(windows.settingsWindow!, as: name, in: folder)
        }
        windows.settingsWindow?.close()

        // Converted files go to a scratch folder, not the real Downloads.
        let output = folder.appendingPathComponent("output", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        settings.saveLocation = .custom
        settings.customFolder = output

        let screen = NSScreen.main!.visibleFrame
        overlay.showFormats(near: NSPoint(x: screen.midX, y: screen.midY))
        await pause()
        save(overlay.panel, as: "bar", in: folder)

        // A file dragged from Finder, dropped on JPEG.
        let sample = folder.appendingPathComponent("sample.png")
        try? samplePNG().write(to: sample)
        let filePasteboard = NSPasteboard(name: .init("RecastSnapshot-files"))
        filePasteboard.clearContents()
        filePasteboard.writeObjects([sample as NSURL])
        await drop(filePasteboard, on: .jpeg, overlay: overlay, snapshot: "bar-hover", folder: folder)
        await waitForResult(overlay)
        save(overlay.panel, as: "result", in: folder)
        report(overlay, label: "file → JPEG")

        // Raw image data plus a link, the way browsers often hand images over, dropped on HEIC.
        overlay.showFormats(near: NSPoint(x: screen.midX, y: screen.midY))
        let browserPasteboard = NSPasteboard(name: .init("RecastSnapshot-browser"))
        browserPasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(samplePNG(), forType: .png)
        item.setString("https://example.com/photos/sunset.png?w=1200", forType: .URL)
        browserPasteboard.writeObjects([item])
        await drop(browserPasteboard, on: .heic, overlay: overlay, snapshot: nil, folder: folder)
        await waitForResult(overlay)
        report(overlay, label: "browser data → HEIC")

        // Something that isn't an image.
        overlay.showFormats(near: NSPoint(x: screen.midX, y: screen.midY))
        let textPasteboard = NSPasteboard(name: .init("RecastSnapshot-text"))
        textPasteboard.clearContents()
        let notes = folder.appendingPathComponent("notes.txt")
        try? Data("hi".utf8).write(to: notes)
        textPasteboard.writeObjects([notes as NSURL])
        await drop(textPasteboard, on: .png, overlay: overlay, snapshot: nil, folder: folder)
        await waitForResult(overlay)
        save(overlay.panel, as: "failure", in: folder)
        report(overlay, label: "text file → PNG")

        for pasteboard in [filePasteboard, browserPasteboard, textPasteboard] {
            pasteboard.releaseGlobally()
        }
    }

    /// Drives `FormatDropView` exactly like AppKit does during a real drag.
    private static func drop(_ pasteboard: NSPasteboard, on format: ImageFormat, overlay: OverlayController, snapshot: String?, folder: URL) async {
        guard let view = overlay.panel.contentView, let index = overlay.model.formats.firstIndex(of: format) else {
            print("SNAPSHOT: \(format.displayName) isn't in the bar")
            return
        }
        let count = overlay.model.formats.count
        let origin = (view.bounds.width - OverlayMetrics.tilesWidth(count: count)) / 2
        let x = origin + CGFloat(index) * (OverlayMetrics.tileSize.width + OverlayMetrics.spacing) + OverlayMetrics.tileSize.width / 2
        let info = FakeDraggingInfo(pasteboard: pasteboard, location: NSPoint(x: x, y: view.bounds.midY - 10), window: overlay.panel)

        let operation = view.draggingEntered(info)
        print("SNAPSHOT: hover \(format.displayName) → operation \(operation.rawValue), highlighted \(overlay.model.highlighted?.displayName ?? "none")")
        if let snapshot {
            await pause()
            save(overlay.panel, as: snapshot, in: folder)
        }
        _ = view.prepareForDragOperation(info)
        let accepted = view.performDragOperation(info)
        print("SNAPSHOT: drop accepted \(accepted)")
    }

    private static func waitForResult(_ overlay: OverlayController) async {
        for _ in 0..<100 {
            switch overlay.model.phase {
            case .finished, .failed:
                await pause()
                return
            default:
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private static func report(_ overlay: OverlayController, label: String) {
        switch overlay.model.phase {
        case .finished(let summary):
            print("SNAPSHOT: \(label): \(summary.title) | \(summary.subtitle) | \(summary.outputs.map(\.path))")
        case .failed(let message):
            print("SNAPSHOT: \(label): failed | \(message)")
        default:
            print("SNAPSHOT: \(label): still converting")
        }
    }

    private static func pause() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    /// Saves the window including its title bar. Blur and glass don't render this way, so transparent panels get a backdrop.
    private static func save(_ window: NSWindow, as name: String, in folder: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)

        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        if !window.isOpaque {
            NSColor(white: 0.93, alpha: 1).setFill()
            NSBezierPath(roundedRect: view.bounds, xRadius: OverlayMetrics.cornerRadius, yRadius: OverlayMetrics.cornerRadius).fill()
        }
        rep.draw(in: view.bounds)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appendingPathComponent("\(name).png"))
    }

    private static func samplePNG() -> Data {
        let image = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { rect in
            NSGradient(colors: [.systemOrange, .systemPink])!.draw(in: rect, angle: 30)
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: NSRect(x: 220, y: 110, width: 60, height: 60)).fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}

private final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    private weak var window: NSWindow?

    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow) {
        draggingPasteboard = pasteboard
        draggingLocation = location
        self.window = window
    }

    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
#endif
