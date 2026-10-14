// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KeyClack",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KeyClack", targets: ["KeyClack"]),
    ],
    targets: [
        // Everything that doesn't need a running app: synthesis, decoding, config, playback.
        .target(name: "KeyClackCore"),
        // The menu-bar app: global key monitor + SwiftUI.
        .executableTarget(name: "KeyClack", dependencies: ["KeyClackCore"]),
        .testTarget(name: "KeyClackCoreTests", dependencies: ["KeyClackCore"]),
    ]
)
