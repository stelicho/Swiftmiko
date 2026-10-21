// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "ScriptDemo",
    // This `platforms:` entry only sets the minimum for Apple
    // platforms — required because SwiftPM needs a consumer's declared
    // macOS floor to be at least as high as a dependency's (Swiftmiko
    // itself requires macOS 14+). It does not restrict Linux or
    // Windows, which aren't governed by this array at all; building
    // there just needs a Swift 6.1+ toolchain, same as the main package.
    platforms: [.macOS(.v14)],
    dependencies: [
        // The Swiftmiko library this whole example exists to demonstrate.
        .package(path: "../../"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "ScriptDemo",
            dependencies: [
                .product(name: "Swiftmiko", package: "Swiftmiko"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            // swift-tools-version 6.1 turns on Swift 6 language mode
            // (full complete-concurrency checking) by default, but
            // Swiftmiko itself is swift-tools-version 5.9 and hasn't
            // been concurrency-audited — BaseConnection (what
            // SSHDispatcher.connectHandler returns) isn't Sendable,
            // which complete checking treats as a hard error on a
            // pinned Swift 6.1 toolchain specifically. Pinning this
            // target to Swift 5 language mode sidesteps that entirely —
            // same fix CommandRunnerTerminalDemo's Package.swift uses,
            // see the comment there for the full explanation.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
