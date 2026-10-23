import AppKit
import RecastCore

/// Notices when the user drags something in any app and holds the trigger keys.
///
/// No Accessibility permission needed: a global mouse-down monitor starts a short-lived poll that watches the
/// drag pasteboard (it changes when a drag begins), the modifier keys and the mouse button. The poll only runs
/// while the button is held.
@MainActor
final class DragMonitor {
    var isEnabled = true
    var trigger: () -> TriggerKey = { .control }
    /// Called once per drag, with the cursor position in screen coordinates.
    var onTrigger: ((NSPoint) -> Void)?
    /// Called when the mouse button is released after a drag.
    var onDragEnded: (() -> Void)?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var mouseDownMonitor: Any?
    private var pollTimer: Timer?
    private var changeCountAtMouseDown = 0
    private var isDragging = false
    private var isConvertible = false
    private var didTrigger = false

    func start() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
    }

    private func mouseDown() {
        guard isEnabled else { return }
        changeCountAtMouseDown = dragPasteboard.changeCount
        isDragging = false
        isConvertible = false
        didTrigger = false

        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // Common modes so it keeps firing while menus or drags track the mouse.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            pollTimer?.invalidate()
            pollTimer = nil
            if isDragging {
                onDragEnded?()
            }
            return
        }

        if !isDragging {
            guard dragPasteboard.changeCount != changeCountAtMouseDown else { return }
            isDragging = true
            isConvertible = ImageIntake.mightContainImages(dragPasteboard.types ?? [])
        }

        guard isConvertible, !didTrigger, NSEvent.modifierFlags.contains(trigger().flags) else { return }
        didTrigger = true
        onTrigger?(NSEvent.mouseLocation)
    }
}
