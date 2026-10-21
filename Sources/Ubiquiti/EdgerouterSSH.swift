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
// Sources/Swiftmiko/Ubiquiti/EdgerouterSSH.swift

import Foundation

/// Ubiquiti EdgeRouter SSH driver (EdgeOS).
///
/// EdgeRouter shares VyOS's commit-based configuration model — it
/// inherits directly from VyOSSSH with a few overrides.
///
/// Maps to netmiko's UbiquitiEdgeRouterSSH(VyOSSSH).
public final class UbiquitiEdgeRouterSSH: VyOSSSH {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation(): unlike VyOS itself,
    /// EdgeRouter's terminal commands have no "set " prefix.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await setTerminalWidth(command: "terminal width 512", pattern: "terminal")
        try await disablePaging(command: "terminal length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save"). Unlike VyOSSSH's own
    /// save_config(), EdgeRouter's "save" command is sent directly at
    /// the normal CLI prompt — it does NOT require entering config
    /// mode first.
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        guard !confirm else {
            throw SwiftmikoError.commandFailed("EdgeRouter does not support save_config confirmation.")
        }
        let output = try await sendCommand(command, stripPrompt: false, stripCommand: false)
        guard output.contains("Done") else {
            throw SwiftmikoError.commandFailed("Save failed with following errors:\n\n\(output)")
        }
        return output
    }
}

// MARK: - UbiquitiEdgeRouterFileTransfer

/// Ubiquiti EdgeRouter SCP File Transfer driver.
///
/// Maps to netmiko's UbiquitiEdgeRouterFileTransfer(BaseFileTransfer).
///
/// EdgeRouter's shell IS its CLI (see sessionPreparation() above —
/// there's no separate shell to drop into), so the Unix-flavored
/// helpers run their commands directly at the normal prompt via
/// BaseConnection's own no-op default enterShellForFileTransfer()/
/// returnFromShellForFileTransfer() hooks — no override needed here.
public final class UbiquitiEdgeRouterFileTransfer: SCPHandler {

    public init(
        connection: BaseConnection,
        sourceFile: String,
        destFile: String,
        fileSystem: String = "/",
        direction: SCPTransferDirection = .put
    ) async throws {
        try await super.init(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destFile,
            fileSystem: fileSystem,
            direction: direction
        )
    }

    override public func checkFileExists(remoteCommand: String = "") async throws -> Bool {
        return try await checkFileExistsUnix(remoteCommand: remoteCommand)
    }

    override public func remoteSpaceAvailable(searchPattern: String = "") async throws -> Int {
        return try await remoteSpaceAvailableUnix(searchPattern: #"[\$#]"#)
    }

    override public func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        return try await remoteFileSizeUnix(remoteCommand: remoteCommand, remoteFile: remoteFile)
    }

    /// EdgeRouter uses a bare "md5sum" rather than the generic
    /// base class's "verify /md5", and its output format requires a
    /// different capture pattern — "(\S+)\s+" (the first whitespace-
    /// delimited token) rather than the base's "=\s+(\S+)".
    ///
    /// Maps to netmiko's remote_md5(base_cmd="md5sum") / the
    /// accompanying process_md5(pattern=r"(\S+)\s+") staticmethod —
    /// Swift's processMD5 can't be polymorphically overridden (it's a
    /// `static func`, not a `class func`), so this reimplements
    /// remoteMD5()'s body directly rather than delegating to super,
    /// passing the EdgeRouter-specific pattern explicitly.
    override public func remoteMD5(
        baseCommand: String = "md5sum",
        remoteFile: String? = nil
    ) async throws -> String {
        let file = remoteFile ?? (direction == .put ? destinationFile : sourceFile)
        let output = try await connection.sendCommand(
            "\(baseCommand) \(fileSystem)/\(file)",
            readTimeout: 300.0,
            stripPrompt: false,
            stripCommand: false
        )
        return try Self.processMD5(output, pattern: #"(\S+)\s+"#)
    }
}
