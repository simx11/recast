// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recast",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Recast", targets: ["Recast"]),
    ],
    targets: [
        // Conversion engine and pasteboard handling, kept free of UI so it can be tested.
        .target(name: "RecastCore"),
        // The menu bar app: drag detection, the format bar, settings.
        .executableTarget(name: "Recast", dependencies: ["RecastCore"]),
        .testTarget(name: "RecastCoreTests", dependencies: ["RecastCore"]),
    ],
    swiftLanguageModes: [.v5]
)
