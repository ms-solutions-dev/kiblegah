// swift-tools-version: 6.2
import PackageDescription

// Duas, Esmaül Hüsna, prayer guide, calendar.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "Duas",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Duas", targets: ["Duas"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../ContentPacks"),
    ],
    targets: [
        .target(
            name: "Duas",
            dependencies: ["Core", "ContentPacks"]),
        .testTarget(name: "DuasTests", dependencies: ["Duas", "ContentPacks"]),
    ]
)
