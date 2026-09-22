// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Swiftmiko",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(name: "Swiftmiko", targets: ["Swiftmiko"]),
        .library(name: "SwiftmikoCLI", targets: ["SwiftmikoCLI"]),
        .executable(name: "swiftmiko-bulk-encrypt", targets: ["BulkEncrypt"]),
        .executable(name: "swiftmiko-cfg", targets: ["Cfg"]),
        .executable(name: "swiftmiko-encrypt", targets: ["Encrypt"]),
        .executable(name: "swiftmiko-grep", targets: ["Grep"]),
        .executable(name: "swiftmiko-show", targets: ["Show"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // Local fork (Sources/swift-nio-ssh) adding classic Diffie-Hellman group14-sha1
        // key exchange for SSH servers too old to offer ECDH/Curve25519 — see
        // Key Exchange/ClassicDiffieHellmanKeyExchange.swift in that checkout.
        .package(path: "Sources/swift-nio-ssh"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        // System-library shim exposing CommonCrypto's AES-CBC primitive, used
        // only by the opt-in legacy-cipher transport (see LegacyCBCTransportProtection.swift).
        .systemLibrary(
            name: "CCommonCryptoShim",
            path: "Sources/CCommonCryptoShim"
        ),
        // Core Library (Explicitly exclude CLITools)
        .target(
            name: "Swiftmiko",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Logging", package: "swift-log"),
                "CCommonCryptoShim"
            ],
            path: "Sources",
            exclude: ["CLITools", "CCommonCryptoShim", "swift-nio-ssh"]
        ),
        // Shared CLI Helper Library
        .target(
            name: "SwiftmikoCLI",
            dependencies: [
                "Swiftmiko",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/CLITools",
            exclude: ["Entrypoints"]
        ),
        // Thin Executables
        .executableTarget(
            name: "BulkEncrypt",
            dependencies: ["SwiftmikoCLI"],
            path: "Sources/CLITools/Entrypoints/BulkEncrypt"
        ),
        .executableTarget(
            name: "Cfg",
            dependencies: ["SwiftmikoCLI"],
            path: "Sources/CLITools/Entrypoints/Cfg"
        ),
        .executableTarget(
            name: "Encrypt",
            dependencies: ["SwiftmikoCLI"],
            path: "Sources/CLITools/Entrypoints/Encrypt"
        ),
        .executableTarget(
            name: "Grep",
            dependencies: ["SwiftmikoCLI"],
            path: "Sources/CLITools/Entrypoints/Grep"
        ),
        .executableTarget(
            name: "Show",
            dependencies: ["SwiftmikoCLI"],
            path: "Sources/CLITools/Entrypoints/Show"
        ),
        .testTarget(
            name: "SwiftmikoTests",
            dependencies: ["Swiftmiko"]
        )
    ]
)
