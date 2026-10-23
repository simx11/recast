import AppKit
import RecastCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var loginItem = LoginItem.shared

    var body: some View {
        Form {
            Section {
                Toggle("Drag to convert", isOn: $settings.isDragToConvertEnabled)
                Picker("Hold while dragging", selection: $settings.trigger) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .disabled(!settings.isDragToConvertEnabled)
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Start dragging an image in any app, then hold \(settings.trigger.label) and drop the image on a format. Press the key after the drag has started.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Save converted images to", selection: $settings.saveLocation) {
                    ForEach(SaveLocation.allCases) { location in
                        Text(location.title).tag(location)
                    }
                }
                if settings.saveLocation == .custom {
                    LabeledContent("Folder") {
                        HStack {
                            Text(settings.customFolder.map { FileManager.default.displayName(atPath: $0.path) } ?? "None")
                                .foregroundStyle(.secondary)
                            Button("Choose…", action: chooseFolder)
                        }
                    }
                }
                Toggle("Show in Finder after converting", isOn: $settings.revealInFinder)
                Toggle("Copy converted image to clipboard", isOn: $settings.copyToClipboard)
            } header: {
                Text("Saving")
            } footer: {
                if settings.saveLocation == .nextToOriginal {
                    Text("Images from a browser or the clipboard have no original folder, so they go to Downloads.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Download the original when a browser only provides a link", isOn: $settings.fetchLinkedImages)
            } header: {
                Text("Browser Images")
            } footer: {
                Text("Conversion always happens on your Mac and nothing is uploaded. This only fetches the image again from the site it came from.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show in menu bar", isOn: $settings.showsMenuBarIcon)
                Toggle("Open Recast at login", isOn: $loginItem.isEnabled)
                if let error = loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("App")
            } footer: {
                if !settings.showsMenuBarIcon {
                    Text("Drag to convert keeps working. To get back here, open Recast again from Applications or Spotlight.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 700)
        .onChange(of: settings.saveLocation) { _, location in
            if location == .custom, settings.customFolder == nil {
                chooseFolder()
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Converted images will be saved here."
        if panel.runModal() == .OK, let url = panel.url {
            settings.customFolder = url
        } else if settings.customFolder == nil {
            settings.saveLocation = .downloads
        }
    }
}

/// Wraps the system login item so the toggle reflects what macOS actually did.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var error: String?

    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct FormatSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ForEach(ImageFormat.allCases) { format in
                    Toggle(isOn: binding(for: format)) {
                        HStack(spacing: 12) {
                            FormatBadge(format: format)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.displayName)
                                Text(format.isAvailable ? format.summary : "This Mac can't write \(format.displayName) files.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!format.isAvailable || isLastEnabled(format))
                }
            } header: {
                Text("Show in the Format Bar")
            }

            Section {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $settings.quality, in: 0.5...1, step: 0.05)
                            .frame(width: 180)
                        Text(settings.quality, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Keep metadata", isOn: $settings.keepMetadata)
            } header: {
                Text("Output")
            } footer: {
                Text("Quality applies to JPEG, HEIC and AVIF. Metadata means camera details, dates and location.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 720)
    }

    private func binding(for format: ImageFormat) -> Binding<Bool> {
        Binding {
            settings.enabledFormats.contains(format) && format.isAvailable
        } set: { isOn in
            if isOn {
                settings.enabledFormats.insert(format)
            } else {
                settings.enabledFormats.remove(format)
            }
        }
    }

    /// The bar always keeps at least one format.
    private func isLastEnabled(_ format: ImageFormat) -> Bool {
        settings.barFormats == [format] && settings.enabledFormats.contains(format)
    }
}

/// A small version of a format bar tile.
struct FormatBadge: View {
    let format: ImageFormat

    var body: some View {
        Text(format.displayName)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 42, height: 26)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(format.isAvailable ? 1 : 0.4)
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Recast").font(.title.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Convert images by dropping them on a format.\nEverything happens on your Mac. Nothing is uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Link("github.com/simx11/recast", destination: URL(string: "https://github.com/simx11/recast")!)
                .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 520, height: 340)
    }
}
