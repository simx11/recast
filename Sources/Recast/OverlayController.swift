import AppKit
import RecastCore
import SwiftUI

/// Layout shared by the SwiftUI format bar and the drop hit-testing, so both agree on where each tile is.
enum OverlayMetrics {
    static let tileSize = CGSize(width: 76, height: 64)
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 10
    static let headerHeight: CGFloat = 24
    static let minimumWidth: CGFloat = 360
    static let cornerRadius: CGFloat = 22
    static let tileCornerRadius = cornerRadius - padding

    static func tilesWidth(count: Int) -> CGFloat {
        CGFloat(count) * tileSize.width + CGFloat(max(count - 1, 0)) * spacing
    }

    static func panelSize(tileCount: Int) -> CGSize {
        CGSize(
            width: max(minimumWidth, tilesWidth(count: tileCount) + 2 * padding),
            height: headerHeight + tileSize.height + 2 * padding
        )
    }

    /// The tile under `x`. Each tile owns a full-height column and half the gap on either side, so there are no dead spots.
    static func tileIndex(atX x: CGFloat, panelWidth: CGFloat, count: Int) -> Int? {
        guard count > 0, x >= 0, x <= panelWidth else { return nil }
        let origin = (panelWidth - tilesWidth(count: count)) / 2
        let index = Int(((x - origin + spacing / 2) / (tileSize.width + spacing)).rounded(.down))
        return min(max(index, 0), count - 1)
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    enum Phase {
        case choosing
        case converting(ImageFormat)
        case finished(ConversionSummary)
        case failed(String)

        var id: String {
            switch self {
            case .choosing, .converting: "bar"
            case .finished: "finished"
            case .failed: "failed"
            }
        }
    }

    @Published var formats: [ImageFormat] = []
    @Published var highlighted: ImageFormat?
    @Published var phase = Phase.choosing
    @Published var isHovering = false
    var dismiss: () -> Void = {}

    var isAcceptingDrops: Bool {
        if case .choosing = phase { true } else { false }
    }
}

@MainActor
final class OverlayController {
    enum Placement { case aboveCursor, belowMenuBar }

    let model = OverlayModel()
    private let settings: AppSettings
    private let service: ConversionService
    private(set) var panel: OverlayPanel!
    private var hideTask: Task<Void, Never>?

    init(settings: AppSettings, service: ConversionService) {
        self.settings = settings
        self.service = service
        panel = OverlayPanel(model: model) { [weak self] intake, format in
            self?.convert(intake, to: format)
        }
        model.dismiss = { [weak self] in self?.hide() }
    }

    /// Shows the format bar just above the cursor while a drag is in progress.
    func showFormats(near point: NSPoint) {
        model.formats = settings.barFormats
        model.highlighted = nil
        model.phase = .choosing
        present(near: point, placement: .aboveCursor)
    }

    /// The drag ended. If it wasn't dropped on the bar, put the bar away.
    func dragEnded() {
        guard panel.isVisible, model.isAcceptingDrops else { return }
        // The drop arrives a moment after the mouse button is released.
        scheduleHide(after: 0.35)
    }

    /// Converts and shows progress, then the result. Pass `point` when the bar isn't on screen yet (menu commands).
    func convert(_ intake: ImageIntake, to format: ImageFormat, presentingNear point: NSPoint? = nil) {
        model.highlighted = format
        model.phase = .converting(format)
        if let point {
            model.formats = settings.barFormats
            present(near: point, placement: .belowMenuBar)
        } else {
            hideTask?.cancel()
            panel.show()
        }

        Task {
            let summary = await service.run(intake, to: format)
            model.phase = summary.outputs.isEmpty ? .failed(summary.subtitle) : .finished(summary)
            panel.show()
            if !summary.outputs.isEmpty {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            scheduleHide(after: summary.outputs.isEmpty ? 5 : 3.5)
        }
    }

    func hide() {
        hideTask?.cancel()
        panel.hide()
    }

    private func present(near point: NSPoint, placement: Placement) {
        hideTask?.cancel()
        let size = OverlayMetrics.panelSize(tileCount: model.formats.count)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let gap: CGFloat = 28

        var origin = NSPoint(x: point.x - size.width / 2, y: 0)
        switch placement {
        case .aboveCursor:
            origin.y = point.y + gap
            if origin.y + size.height > visible.maxY {
                origin.y = point.y - gap - size.height
            }
        case .belowMenuBar:
            origin.y = visible.maxY - size.height - 12
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.show()
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            if model.isHovering, !model.isAcceptingDrops {
                scheduleHide(after: 1)
            } else {
                panel.hide()
            }
        }
    }
}

/// A floating panel that never activates Recast, so the app you're dragging from stays in front.
final class OverlayPanel: NSPanel {
    init(model: OverlayModel, onDrop: @escaping (ImageIntake, ImageFormat) -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: OverlayMetrics.panelSize(tileCount: 1)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = FormatDropView(model: model, onDrop: onDrop)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        invalidateShadow()
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // Skip if the panel was shown again while fading.
            guard let self, alphaValue == 0 else { return }
            orderOut(nil)
        }
    }
}

/// Receives drops for the whole panel and works out which format tile is under the cursor.
final class FormatDropView: NSView {
    private let model: OverlayModel
    private let onDrop: (ImageIntake, ImageFormat) -> Void

    init(model: OverlayModel, onDrop: @escaping (ImageIntake, ImageFormat) -> Void) {
        self.model = model
        self.onDrop = onDrop
        super.init(frame: .zero)

        let hostingView = DropTransparentHostingView(rootView: OverlayView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        registerForDraggedTypes(ImageIntake.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated {
            if model.isAcceptingDrops {
                model.highlighted = nil
            }
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { model.isAcceptingDrops && format(at: sender) != nil }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated {
            guard model.isAcceptingDrops, let format = format(at: sender) else { return false }
            // Read the pasteboard now; it's gone once this method returns.
            onDrop(ImageIntake(pasteboard: sender.draggingPasteboard), format)
            return true
        }
    }

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated {
            guard model.isAcceptingDrops else { return [] }
            let format = format(at: sender)
            if format != model.highlighted {
                model.highlighted = format
                if format != nil {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            guard format != nil else { return [] }
            return sender.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
        }
    }

    @MainActor
    private func format(at sender: NSDraggingInfo) -> ImageFormat? {
        let point = convert(sender.draggingLocation, from: nil)
        return OverlayMetrics.tileIndex(atX: point.x, panelWidth: bounds.width, count: model.formats.count)
            .map { model.formats[$0] }
    }
}

/// SwiftUI must not claim drags itself, or they'd never reach `FormatDropView`.
final class DropTransparentHostingView<Content: View>: NSHostingView<Content> {
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}
}
