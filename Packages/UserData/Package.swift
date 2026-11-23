// swift-tools-version: 6.2
import PackageDescription

// Settings, reading position, notes, favourites, dhikr – all keyed.
//
// macOS is included so that `swift test` answers on the Mac in seconds.
let package = Package(
    name: "UserData",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "UserData", targets: ["UserData"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "UserData",
            dependencies: ["Core"]),
        .testTarget(name: "UserDataTests", dependencies: ["UserData"]),
    ]
)
