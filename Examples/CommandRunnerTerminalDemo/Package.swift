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
            ]
        )
    ]
)
