// swift-tools-version: 6.2
import PackageDescription

// Tokens Seher/Sakin (light, dark, by prayer time), type roles on Dynamic Type, components. The only place with hex values.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: ["Core"],
            resources: [.copy("YaziTipleri")]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    ]
)
