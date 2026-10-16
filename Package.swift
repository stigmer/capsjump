// swift-tools-version: 6.0
//
// CapsJump: one Mac app for shortcuts built around Caps Lock. Hold it and press a key to
// bring an app forward, land on a site's tab in the right Chrome account, snap the front
// window, or open a link. CapsJumpCore is the pure logic and carries nearly every test;
// CapsJumpChrome is the live side of a jump (Apple Events, Accessibility, launching
// Chrome); CapsJumpSystem is the live side of the keys (the key mapping, the event tap,
// the config watcher and saving the config, moving windows, opening apps and links);
// CapsJumpApp runs the keys and receives capsjump:// links; capsjump is the CLI. Saving
// the config is the one live piece with tests of its own (CapsJumpSystemTests), because
// its bugs would lose the user's file. scripts/bundle.sh puts the app and the CLI into
// one CapsJump.app.

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
        .target(
            name: "CapsJumpSystem",
            dependencies: ["CapsJumpCore"]
        ),
        .executableTarget(
            name: "CapsJumpApp",
            dependencies: ["CapsJumpCore", "CapsJumpChrome", "CapsJumpSystem"]
        ),
        .executableTarget(
            name: "capsjump",
            dependencies: [
                "CapsJumpCore",
                "CapsJumpChrome",
                "CapsJumpSystem",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CapsJumpCoreTests",
            dependencies: ["CapsJumpCore"]
        ),
        .testTarget(
            name: "CapsJumpSystemTests",
            dependencies: ["CapsJumpCore", "CapsJumpSystem"]
        ),
    ]
)
