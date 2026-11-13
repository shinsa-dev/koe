// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Koe",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet on the Neural Engine, and Whisper. Both download their models from Hugging Face on demand.
        .package(url: "https://github.com/FluidInference/FluidAudio", .upToNextMinor(from: "0.9.1")),
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMinor(from: "1.1.1")),
        // Updates from shinsa.dev/koe. Its framework ships in Koe.app/Contents/Frameworks (build.sh).
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.10.1")),
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
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Koe",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "KoeCoreTests",
            dependencies: ["KoeCore"],
            path: "Tests/KoeCoreTests"
        ),
    ]
)
