import Foundation

public enum OutputNaming {
    /// Writes `data` as “name.ext”, or “name 2.ext”, “name 3.ext”… if that's taken, the way Finder does. Never overwrites.
    public static func write(_ data: Data, baseName: String, fileExtension: String, in directory: URL) throws -> URL {
        let base = sanitized(baseName)
        for attempt in 1...9_999 {
            let name = attempt == 1 ? base : "\(base) \(attempt)"
            let url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Makes a string safe to use as a file name.
    public static func sanitized(_ name: String) -> String {
        var result = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading dot would hide the file.
        result = String(result.drop(while: { $0 == "." }))
        if result.count > 120 {
            result = String(result.prefix(120))
        }
        return result.isEmpty ? "Image" : result
    }
}
