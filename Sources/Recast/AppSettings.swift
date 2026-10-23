import AppKit
import RecastCore

/// The modifier keys that bring up the format bar during a drag.
enum TriggerKey: String, CaseIterable, Identifiable {
    case control, option, command, shift, controlOption, controlShift

    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .control: [.control]
        case .option: [.option]
        case .command: [.command]
        case .shift: [.shift]
        case .controlOption: [.control, .option]
        case .controlShift: [.control, .shift]
        }
    }

    var symbols: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        case .shift: "⇧"
        case .controlOption: "⌃⌥"
        case .controlShift: "⌃⇧"
        }
    }

    var name: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        case .controlOption: "Control-Option"
        case .controlShift: "Control-Shift"
        }
    }

    var label: String { "\(symbols) \(name)" }
}

enum SaveLocation: String, CaseIterable, Identifiable {
    case nextToOriginal, downloads, desktop, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextToOriginal: "Next to the Original"
        case .downloads: "Downloads"
        case .desktop: "Desktop"
        case .custom: "Other Folder…"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var isDragToConvertEnabled: Bool { didSet { defaults.set(isDragToConvertEnabled, forKey: Key.enabled) } }
    @Published var trigger: TriggerKey { didSet { defaults.set(trigger.rawValue, forKey: Key.trigger) } }
    @Published var enabledFormats: Set<ImageFormat> { didSet { defaults.set(enabledFormats.map(\.rawValue).sorted(), forKey: Key.formats) } }
    @Published var quality: Double { didSet { defaults.set(quality, forKey: Key.quality) } }
    @Published var keepMetadata: Bool { didSet { defaults.set(keepMetadata, forKey: Key.keepMetadata) } }
    @Published var saveLocation: SaveLocation { didSet { defaults.set(saveLocation.rawValue, forKey: Key.saveLocation) } }
    @Published var customFolder: URL? { didSet { defaults.set(customFolder?.path, forKey: Key.customFolder) } }
    @Published var revealInFinder: Bool { didSet { defaults.set(revealInFinder, forKey: Key.revealInFinder) } }
    @Published var copyToClipboard: Bool { didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) } }
    @Published var fetchLinkedImages: Bool { didSet { defaults.set(fetchLinkedImages, forKey: Key.fetchLinkedImages) } }

    var hasSeenWelcome: Bool {
        get { defaults.bool(forKey: Key.hasSeenWelcome) }
        set { defaults.set(newValue, forKey: Key.hasSeenWelcome) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isDragToConvertEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        trigger = defaults.string(forKey: Key.trigger).flatMap(TriggerKey.init) ?? .control
        enabledFormats = (defaults.stringArray(forKey: Key.formats)).map { Set($0.compactMap(ImageFormat.init)) } ?? ImageFormat.defaultSelection
        quality = defaults.object(forKey: Key.quality) as? Double ?? 0.85
        keepMetadata = defaults.object(forKey: Key.keepMetadata) as? Bool ?? true
        saveLocation = defaults.string(forKey: Key.saveLocation).flatMap(SaveLocation.init) ?? .nextToOriginal
        customFolder = defaults.string(forKey: Key.customFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
        revealInFinder = defaults.bool(forKey: Key.revealInFinder)
        copyToClipboard = defaults.bool(forKey: Key.copyToClipboard)
        fetchLinkedImages = defaults.object(forKey: Key.fetchLinkedImages) as? Bool ?? true
    }

    /// Formats in the format bar, in a fixed order.
    var barFormats: [ImageFormat] {
        let formats = ImageFormat.allCases.filter { enabledFormats.contains($0) && $0.isAvailable }
        return formats.isEmpty ? [.png] : formats
    }

    var conversionOptions: ConversionOptions {
        ConversionOptions(quality: quality, keepMetadata: keepMetadata)
    }

    /// Where a converted image goes. Images without a folder of their own (from a browser or the clipboard) go to Downloads.
    func outputFolder(forOriginalIn original: URL?) -> URL {
        switch saveLocation {
        case .nextToOriginal:
            if let original, FileManager.default.isWritableFile(atPath: original.path) {
                return original
            }
            return Self.downloads
        case .downloads:
            return Self.downloads
        case .desktop:
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .custom:
            return customFolder ?? Self.downloads
        }
    }

    static let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    private enum Key {
        static let enabled = "dragToConvertEnabled"
        static let trigger = "trigger"
        static let formats = "enabledFormats"
        static let quality = "quality"
        static let keepMetadata = "keepMetadata"
        static let saveLocation = "saveLocation"
        static let customFolder = "customFolder"
        static let revealInFinder = "revealInFinder"
        static let copyToClipboard = "copyToClipboard"
        static let fetchLinkedImages = "fetchLinkedImages"
        static let hasSeenWelcome = "hasSeenWelcome"
    }
}
