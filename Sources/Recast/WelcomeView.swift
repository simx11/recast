import AppKit
import SwiftUI

struct WelcomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    var onOpenSettings: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text("Welcome to Recast")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 8)
            Text("Convert any image by dropping it on a format.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 18) {
                Step(symbol: "hand.draw", title: "Start dragging an image", detail: "From Safari, Chrome, Finder, Mail or any other app.")
                Step(symbol: "keyboard", title: "Hold \(settings.trigger.label)", detail: "Press it once the drag has started, and the format bar pops up above your cursor. You can pick another key in Settings.")
                Step(symbol: "tray.and.arrow.down", title: "Drop it on a format", detail: saveDetail)
            }
            .padding(.vertical, 28)

            Label("Everything happens on your Mac. Nothing is uploaded.", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            Label("Recast lives in the menu bar.", systemImage: "photo.on.rectangle.angled")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack {
                Button("Settings…", action: onOpenSettings)
                Spacer()
                Button("Get Started", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 28)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 500)
    }

    /// Where the file ends up with the current settings.
    private var saveDetail: String {
        switch settings.saveLocation {
        case .nextToOriginal:
            "The converted copy is saved next to the original. Images from a browser go to Downloads."
        case .downloads:
            "The converted copy is saved to Downloads."
        case .desktop:
            "The converted copy is saved to your Desktop."
        case .custom:
            "The converted copy is saved to \(settings.customFolder.map { FileManager.default.displayName(atPath: $0.path) } ?? "Downloads")."
        }
    }
}

private struct Step: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
