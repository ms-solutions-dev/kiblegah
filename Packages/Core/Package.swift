// swift-tools-version: 6.2
import PackageDescription

// Keys, Turkish text rules, time arithmetic. Depends on nothing.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "Core",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Core",
            dependencies: []),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ]
)
