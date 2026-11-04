// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [.macOS(.v26)],
    targets: [
        // Everything that can be decided without AppKit: the session timeline, the bundle composer,
        // the setup checklist. Kept pure so it is unit-tested without launching the app.
        .target(
            name: "KoeCore",
            path: "Sources/KoeCore"
        ),
        .executableTarget(
            name: "Koe",
            dependencies: ["KoeCore"],
            path: "Sources/Koe"
        ),
        .testTarget(
            name: "KoeCoreTests",
            dependencies: ["KoeCore"],
            path: "Tests/KoeCoreTests"
        ),
    ]
)
