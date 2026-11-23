// swift-tools-version: 6.2
import PackageDescription

// Direction to the Kaaba, flat/upright pose, states.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "Qibla",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "Qibla", targets: ["Qibla"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "Qibla",
            dependencies: ["Core"]),
        .testTarget(name: "QiblaTests", dependencies: ["Qibla", "Core"]),
    ]
)
