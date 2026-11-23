// swift-tools-version: 6.2
import PackageDescription

// All shared screens. Knows only roles from DesignSystem, no hex values.
// Optional features of other app targets come in via `Plugin`, never as a dependency.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Features", targets: ["Features"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../ContentPacks"),
        .package(path: "../PrayerTimes"),
        .package(path: "../Qibla"),
        .package(path: "../Quran"),
        .package(path: "../Duas"),
        .package(path: "../UserData"),
        .package(path: "../WidgetBridge"),
    ],
    targets: [
        .target(
            name: "Features",
            dependencies: [
                "Core", "DesignSystem", "ContentPacks", "PrayerTimes", "Qibla", "Quran", "Duas",
                "UserData",
                "WidgetBridge",
            ]),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"]),
    ]
)
