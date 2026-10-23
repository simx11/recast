import AppKit
import RecastCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .panelBackground()
            .onHover { model.isHovering = $0 }
            .animation(.snappy(duration: 0.22), value: model.phase.id)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .choosing:
            FormatBar(formats: model.formats, highlighted: model.highlighted, converting: nil)
        case .converting(let format) where model.formats.contains(format):
            FormatBar(formats: model.formats, highlighted: format, converting: format)
        case .converting(let format):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Converting to \(format.displayName)…").font(.system(size: 13, weight: .medium))
            }
        case .finished(let summary):
            ResultRow(summary: summary, dismiss: model.dismiss)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .failed(let message):
            FailureRow(message: message)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

private struct FormatBar: View {
    let formats: [ImageFormat]
    let highlighted: ImageFormat?
    let converting: ImageFormat?

    var body: some View {
        VStack(spacing: 0) {
            Text("Convert to")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(height: OverlayMetrics.headerHeight)
            HStack(spacing: OverlayMetrics.spacing) {
                ForEach(formats) { format in
                    FormatTile(format: format, isHighlighted: format == highlighted, isConverting: format == converting)
                        .frame(width: OverlayMetrics.tileSize.width, height: OverlayMetrics.tileSize.height)
                }
            }
        }
        .padding(OverlayMetrics.padding)
    }
}

private struct FormatTile: View {
    let format: ImageFormat
    let isHighlighted: Bool
    let isConverting: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(format.displayName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            ZStack {
                if isConverting {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(format.caption)
                        .font(.system(size: 10, weight: .medium))
                        .opacity(isHighlighted ? 0.85 : 0.6)
                }
            }
            .frame(height: 14)
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: OverlayMetrics.tileCornerRadius, style: .continuous)
                .fill(isHighlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
        }
        .scaleEffect(isHighlighted ? 1.05 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHighlighted)
        .accessibilityElement(children: .combine)
    }
}

private struct ResultRow: View {
    let summary: ConversionSummary
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(summary.outputs)
                dismiss()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = summary.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator)
            }

            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.green))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .offset(x: 6, y: 6)
        }
        // Drag the converted file straight into another app.
        .onDrag { NSItemProvider(contentsOf: summary.outputs[0]) ?? NSItemProvider() }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(summary.outputs[0])
            dismiss()
        }
        .help("Drag the converted image anywhere, or double-click to open it")
    }
}

private struct FailureRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't convert").font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

private extension View {
    /// Liquid Glass on macOS 26 and later, a HUD blur before that.
    @ViewBuilder
    func panelBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: OverlayMetrics.cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(VisualEffectBackground().clipShape(shape))
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
