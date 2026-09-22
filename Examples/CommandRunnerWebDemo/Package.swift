// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "CommandRunnerWebDemo",
    platforms: [
        // Matches Swiftmiko's own minimum, which is stricter than
        // Vapor's (macOS 13+).
        .macOS(.v14)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        // 🍃 Templating for the server-rendered HTML pages.
        .package(url: "https://github.com/vapor/leaf.git", from: "4.5.1"),
        // The Swiftmiko library this whole example exists to demonstrate.
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "CommandRunnerWebDemo",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Swiftmiko", package: "Swiftmiko")
            ]
            // Resources/Views and Public/ are read directly off disk at
            // runtime (Vapor's own convention), relative to the working
            // directory `swift run` is launched from — not bundled via
            // SPM's resource-copying mechanism.
        )
    ]
)
