import AppKit
import RecastCore

/// The menu bar icon and its menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    var onConvertFiles: (ImageFormat) -> Void = { _ in }
    var onConvertClipboard: (ImageFormat) -> Void = { _ in }
    var onShowSettings: () -> Void = {}
    var onShowWelcome: () -> Void = {}

    private let settings: AppSettings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    /// Bottom-centre of the menu bar icon, in screen coordinates.
    var anchorPoint: NSPoint? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSPoint(x: frame.midX, y: frame.minY)
    }

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        let image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Recast")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hint = NSMenuItem(title: "Drag an image and hold \(settings.trigger.symbols) to convert", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        menu.addItem(submenuItem("Convert Images To", action: #selector(convertFiles(_:))))
        let clipboard = submenuItem("Convert Clipboard Image To", action: #selector(convertClipboard(_:)))
        clipboard.isEnabled = ImageIntake.mightContainImages(NSPasteboard.general.types ?? [])
        menu.addItem(clipboard)
        menu.addItem(.separator())

        let toggle = item("Drag to Convert", action: #selector(toggleDragToConvert))
        toggle.state = settings.isDragToConvertEnabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(item("How to Use Recast", action: #selector(showWelcome)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Recast", action: #selector(quit), key: "q"))
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenuItem(_ title: String, action: Selector) -> NSMenuItem {
        let submenu = NSMenu()
        for format in ImageFormat.allCases where format.isAvailable {
            let entry = item(format.displayName, action: action)
            entry.representedObject = format.rawValue
            submenu.addItem(entry)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func format(of sender: NSMenuItem) -> ImageFormat? {
        (sender.representedObject as? String).flatMap(ImageFormat.init)
    }

    @objc private func convertFiles(_ sender: NSMenuItem) {
        format(of: sender).map(onConvertFiles)
    }

    @objc private func convertClipboard(_ sender: NSMenuItem) {
        format(of: sender).map(onConvertClipboard)
    }

    @objc private func toggleDragToConvert() {
        settings.isDragToConvertEnabled.toggle()
    }

    @objc private func showSettings() {
        onShowSettings()
    }

    @objc private func showWelcome() {
        onShowWelcome()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
