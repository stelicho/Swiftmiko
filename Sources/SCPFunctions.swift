//
//  ┌───────────────────────────────────────────────────────┐
//  │                   S W I F T M I K O                   │
//  │  Swift-Native Multi-Vendor Network Device Automation  │
//  └───────────────────────────────────────────────────────┘
//
//  Author & Maintainer: K.K. Campbell
//  Created with the assistance of Claude Sonnet 5 (Anthropic),
//  via Claude Code.
//
//
//  SCPFunctions.swift
//  Swiftmiko
//
//  Port of netmiko/scp_functions.py
//

import Foundation

public typealias InlineTransferFactory = @Sendable (
    _ connection: BaseConnection,
    _ sourceFile: String,
    _ destinationFile: String,
    _ fileSystem: String?
) async throws -> SCPHandler

/// Progress bar equivalent to Netmiko's default callback.
///
/// The callback prints a terminal-friendly 50-character bar. `filename` is
/// already a Swift `String`, so the Python bytes/string conversion is not
/// needed.
public func progressBar(
    filename: String,
    size: Int,
    sent: Int,
    peerName: String? = nil
) {
    let maxWidth = 50
    let safeSize = max(size, 1)
    let percentComplete = min(max(Double(sent) / Double(safeSize), 0.0), 1.0)
    let percent = String(format: "%.2f%%", percentComplete * 100.0)
    let hashCount = min(Int(percentComplete * Double(maxWidth)), maxWidth)
    let progress = String(repeating: ">", count: hashCount)
        .padding(
            toLength: maxWidth,
            withPad: " ",
            startingAt: 0
        )
    let header: String
    if let peerName {
        header = "Transferring file to \(peerName): \(filename)"
    } else {
        header = "Transferring file: \(filename)"
    }

    // ANSI clear-screen matches Netmiko's default visual behavior.
    print("\u{001B}[2J")
    print(header)
    print("\(progress)| (\(percent))")
}

/// Verify remote/local capacity, then perform the transfer.
public func verifySpaceAndTransferFile(
    _ transfer: SCPHandler
) async throws {
    guard try await transfer.verifySpaceAvailable() else {
        throw SwiftmikoError.connectionFailed(
            "Insufficient space available on the destination filesystem"
        )
    }
    try await transferForOperation(transfer)
}

/// Result returned by `fileTransfer`.
///
/// This replaces Netmiko's dictionary with a strongly typed value while
/// retaining the same three result fields.
public struct FileTransferResult: Sendable {
    public let fileExists: Bool
    public let fileTransferred: Bool
    public let fileVerified: Bool

    public init(
        fileExists: Bool,
        fileTransferred: Bool,
        fileVerified: Bool
    ) {
        self.fileExists = fileExists
        self.fileTransferred = fileTransferred
        self.fileVerified = fileVerified
    }

    /// Dictionary-shaped representation for callers migrating from Python.
    public var dictionary: [String: Bool] {
        [
            "file_exists": fileExists,
            "file_transferred": fileTransferred,
            "file_verified": fileVerified
        ]
    }
}

/// Transfer a file using SCP or Cisco IOS inline transfer.
///
/// `inlineTransfer` is supported only for Cisco IOS and IOS-XE, matching
/// Netmiko. The regular SCP path uses `FileTransfer`; callers provide the
/// concrete `SCPClient` through `scpClient`.
@discardableResult
public func fileTransfer(
    sshConnection: BaseConnection,
    sourceFile: String,
    destinationFile: String,
    fileSystem: String? = nil,
    direction: SCPTransferDirection = .put,
    disableMD5: Bool = false,
    inlineTransfer: Bool = false,
    overwriteFile: Bool = false,
    socketTimeout: TimeInterval = 10.0,
    progress: SCPProgressCallback? = nil,
    progress4: SCPProgressCallback? = nil,
    verifyFile: Bool? = nil,
    scpClient: SCPClient? = nil,
    inlineTransferFactory: InlineTransferFactory? = nil
) async throws -> FileTransferResult {
    let deviceType = sshConnection.profile.deviceType
    let isCiscoIOS = deviceType.contains("cisco_ios") ||
        deviceType.contains("cisco_xe")

    if inlineTransfer && !isCiscoIOS {
        throw SwiftmikoError.connectionFailed(
            "Inline transfer is only supported for Cisco IOS/Cisco IOS-XE"
        )
    }

    // `verifyFile` supersedes `disableMD5`, preserving Netmiko's migration
    // behavior.
    let shouldVerify = verifyFile ?? !disableMD5

    let transfer: SCPHandler
    if inlineTransfer {
        guard let inlineTransferFactory else {
            throw SwiftmikoError.notImplemented(
                "Cisco inline transfer requires an InlineTransferFactory"
            )
        }
        transfer = try await inlineTransferFactory(
            sshConnection,
            sourceFile,
            destinationFile,
            fileSystem
        )
    } else {
        transfer = try await FileTransfer(
            connection: sshConnection,
            sourceFile: sourceFile,
            destinationFile: destinationFile,
            fileSystem: fileSystem,
            direction: direction,
            socketTimeout: socketTimeout,
            progress: progress,
            progress4: progress4,
            hashSupported: shouldVerify,
            scpClient: scpClient
        )
    }

    if !inlineTransfer {
        try await transfer.establishSCPConnection()
    }

    do {
        let exists = try await transfer.checkFileExists()

        if exists {
            if overwriteFile {
                if shouldVerify, try await verifyTransfer(transfer) {
                    await transfer.closeSCPChannel()
                    return FileTransferResult(
                        fileExists: true,
                        fileTransferred: false,
                        fileVerified: true
                    )
                }

                try await verifySpaceAndTransferFile(transfer)
                if shouldVerify {
                    guard try await verifyTransfer(transfer) else {
                        throw SwiftmikoError.connectionFailed(
                            "MD5 failure between source and destination files"
                        )
                    }
                    await transfer.closeSCPChannel()
                    return FileTransferResult(
                        fileExists: true,
                        fileTransferred: true,
                        fileVerified: true
                    )
                }

                await transfer.closeSCPChannel()
                return FileTransferResult(
                    fileExists: true,
                    fileTransferred: true,
                    fileVerified: false
                )
            }

            if shouldVerify, try await verifyTransfer(transfer) {
                await transfer.closeSCPChannel()
                return FileTransferResult(
                    fileExists: true,
                    fileTransferred: false,
                    fileVerified: true
                )
            }

            throw SwiftmikoError.connectionFailed(
                "File already exists and overwriteFile is disabled"
            )
        }

        try await verifySpaceAndTransferFile(transfer)
        if shouldVerify {
            guard try await verifyTransfer(transfer) else {
                throw SwiftmikoError.connectionFailed(
                    "MD5 failure between source and destination files"
                )
            }
            await transfer.closeSCPChannel()
            return FileTransferResult(
                fileExists: false,
                fileTransferred: true,
                fileVerified: true
            )
        }

        await transfer.closeSCPChannel()
        return FileTransferResult(
            fileExists: false,
            fileTransferred: true,
            fileVerified: false
        )
    } catch {
        await transfer.closeSCPChannel()
        throw error
    }
}

/// Inline IOS transfer has a different public operation (`transfer`) because
/// it writes through the existing CLI channel rather than an SCP channel.
private func transferForOperation(_ transfer: SCPHandler) async throws {
    try await transfer.transferFile()
}

private func verifyTransfer(_ transfer: SCPHandler) async throws -> Bool {
    return try await transfer.verifyFile()
}
