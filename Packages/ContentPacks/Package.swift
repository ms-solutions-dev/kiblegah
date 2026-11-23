// swift-tools-version: 6.2
import PackageDescription

// Content packs (SQLite + manifest) and the ContentProvider interface.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "ContentPacks",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ContentPacks", targets: ["ContentPacks"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "ContentPacks",
            dependencies: ["Core"]),
        .testTarget(name: "ContentPacksTests", dependencies: ["ContentPacks"]),
    ]
)
