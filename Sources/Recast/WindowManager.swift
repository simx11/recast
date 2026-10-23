import AppKit
import SwiftUI

/// Owns the settings and welcome windows. Recast has no Dock icon, so it activates itself when showing one.
@MainActor
final class WindowManager {
    private(set) var settingsWindow: NSWindow?
    private(set) var welcomeWindow: NSWindow?

    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        present(window)
    }

    func showWelcome() {
        let window = welcomeWindow ?? makeWelcomeWindow()
        welcomeWindow = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        // Toolbar tabs, like System Settings-era preference windows.
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("General", symbol: "gearshape", view: GeneralSettingsView()))
        tabs.addTabViewItem(tab("Formats", symbol: "photo.stack", view: FormatSettingsView()))
        tabs.addTabViewItem(tab("About", symbol: "info.circle", view: AboutView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        return window
    }

    private func tab(_ label: String, symbol: String, view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    private func makeWelcomeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let controller = NSHostingController(rootView: WelcomeView(
            onOpenSettings: { [weak self, weak window] in
                window?.close()
                self?.showSettings()
            },
            onDone: { [weak window] in window?.close() }
        ))
        controller.sizingOptions = .preferredContentSize
        window.contentViewController = controller
        return window
    }
}
