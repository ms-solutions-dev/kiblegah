// swift-tools-version: 6.2
import PackageDescription

// Prayer time sources (server, device), stock, derived values, notification planner.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "PrayerTimes",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PrayerTimes", targets: ["PrayerTimes"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "PrayerTimes",
            dependencies: ["Core"],
            resources: [.copy("Resources/hicri-diyanet.json")]),
        .testTarget(
            name: "PrayerTimesTests", dependencies: ["PrayerTimes", "Core"], resources: [.copy("Veri")]),
    ]
)
