// swift-tools-version: 6.0
//
// CapsJump: one Mac app that brings forward a site's tab in the right Chrome
// account, or opens it there. CapsJumpCore is the pure logic and carries every
// test; CapsJumpChrome is the live side (Apple Events, Accessibility, launching
// Chrome); CapsJumpApp receives capsjump:// links; capsjump is the CLI.
// scripts/bundle.sh puts the app and the CLI into one CapsJump.app.

import PackageDescription

let package = Package(
    name: "CapsJump",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CapsJumpApp", targets: ["CapsJumpApp"]),
        .executable(name: "capsjump", targets: ["capsjump"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    ],
    targets: [
        .target(
            name: "CapsJumpCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .target(
            name: "CapsJumpChrome",
            dependencies: ["CapsJumpCore"]
        ),
        .executableTarget(
            name: "CapsJumpApp",
            dependencies: ["CapsJumpCore", "CapsJumpChrome"]
        ),
        .executableTarget(
            name: "capsjump",
            dependencies: [
                "CapsJumpCore",
                "CapsJumpChrome",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CapsJumpCoreTests",
            dependencies: ["CapsJumpCore"]
        ),
    ]
)
