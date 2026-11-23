// swift-tools-version: 6.2
import PackageDescription

// Snapshot shared by the app and the widget. Foundation only.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "WidgetBridge",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "WidgetBridge", targets: ["WidgetBridge"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WidgetBridge",
            dependencies: []),
        .testTarget(name: "WidgetBridgeTests", dependencies: ["WidgetBridge"]),
    ]
)
