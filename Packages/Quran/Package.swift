// swift-tools-version: 6.2
import PackageDescription

// Word-level reading model, reading events, playback.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "Quran",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Quran", targets: ["Quran"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../ContentPacks"),
    ],
    targets: [
        .target(
            name: "Quran",
            dependencies: ["Core", "ContentPacks"]),
        .testTarget(name: "QuranTests", dependencies: ["Quran", "Core"]),
    ]
)
