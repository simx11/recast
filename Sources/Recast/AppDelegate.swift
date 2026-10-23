import AppKit
import Combine
import RecastCore
import UniformTypeIdentifiers

@main
enum RecastMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let windows = WindowManager()
    private let dragMonitor = DragMonitor()
    private lazy var overlay = OverlayController(settings: settings, service: ConversionService(settings: settings))
    private var statusMenu: StatusMenu!
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(settings: settings)
        statusMenu.onConvertFiles = { [weak self] in self?.convertFiles(to: $0) }
        statusMenu.onConvertClipboard = { [weak self] in self?.convertClipboard(to: $0) }
        statusMenu.onShowSettings = { [weak self] in self?.windows.showSettings() }
        statusMenu.onShowWelcome = { [weak self] in self?.windows.showWelcome() }

        dragMonitor.trigger = { [settings] in settings.trigger }
        dragMonitor.onTrigger = { [weak self] point in self?.overlay.showFormats(near: point) }
        dragMonitor.onDragEnded = { [weak self] in self?.overlay.dragEnded() }
        settings.$isDragToConvertEnabled
            .sink { [dragMonitor] in dragMonitor.isEnabled = $0 }
            .store(in: &subscriptions)
        settings.$showsMenuBarIcon
            .sink { [statusMenu] in statusMenu?.isVisible = $0 }
            .store(in: &subscriptions)
        dragMonitor.start()

        #if DEBUG
        if DebugSnapshots.runIfRequested(windows: windows, overlay: overlay, settings: settings) { return }
        #endif

        if !settings.hasSeenWelcome {
            settings.hasSeenWelcome = true
            windows.showWelcome()
        }
    }

    /// Opening Recast again (from Finder or Spotlight) while it's running shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showSettings()
        return false
    }

    private func convertFiles(to format: ImageFormat) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Convert to \(format.displayName)"
        panel.prompt = "Convert"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        overlay.convert(ImageIntake(fileURLs: panel.urls), to: format, presentingNear: anchorPoint)
    }

    private func convertClipboard(to format: ImageFormat) {
        overlay.convert(ImageIntake(pasteboard: .general), to: format, presentingNear: anchorPoint)
    }

    private var anchorPoint: NSPoint {
        statusMenu.anchorPoint ?? NSEvent.mouseLocation
    }
}
