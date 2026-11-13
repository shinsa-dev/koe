// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet on the Neural Engine, and Whisper. Both download their models from Hugging Face on demand.
        .package(url: "https://github.com/FluidInference/FluidAudio", .upToNextMinor(from: "0.9.1")),
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMinor(from: "1.1.1")),
    ],
    targets: [
        // Everything that can be decided without AppKit: the session timeline, the bundle composer,
        // the setup checklist. Kept pure so it is unit-tested without launching the app.
        .target(
            name: "KoeCore",
            path: "Sources/KoeCore"
        ),
        .executableTarget(
            name: "Koe",
            dependencies: [
                "KoeCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Koe"
        ),
        .testTarget(
            name: "KoeCoreTests",
            dependencies: ["KoeCore"],
            path: "Tests/KoeCoreTests"
        ),
    ]
)
