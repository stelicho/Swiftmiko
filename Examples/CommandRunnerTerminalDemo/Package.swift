// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "CommandRunnerTerminalDemo",
    // This `platforms:` entry only sets the minimum for Apple
    // platforms — required because SwiftPM needs a consumer's declared
    // macOS floor to be at least as high as a dependency's (Swiftmiko
    // itself requires macOS 14+). It does not restrict Linux or
    // Windows, which aren't governed by this array at all; building
    // there just needs a Swift 6.1+ toolchain, same as the main package.
    platforms: [.macOS(.v14)],
    dependencies: [
        // The Swiftmiko library this whole example exists to demonstrate.
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "CommandRunnerTerminalDemo",
            dependencies: [
                .product(name: "Swiftmiko", package: "Swiftmiko")
            ],
            // swift-tools-version 6.1 turns on Swift 6 language mode
            // (full complete-concurrency checking) by default, but
            // Swiftmiko itself is swift-tools-version 5.9 and hasn't
            // been concurrency-audited — BaseConnection (what
            // SSHDispatcher.connectHandler returns) isn't Sendable,
            // which complete checking treats as a hard error on a
            // pinned Swift 6.1 toolchain specifically (a newer local
            // toolchain's more advanced region-isolation inference
            // papered over it, which is what made this look fine
            // before it failed in CI). Pinning this target to Swift 5
            // language mode is the same mechanism every other
            // Examples/ app already relies on without knowing it —
            // their Xcode projects default to SWIFT_VERSION = 5.0,
            // which is why none of them hit this despite using the
            // identical BaseConnection pattern.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
