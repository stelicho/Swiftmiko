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
// Sources/Swiftmiko/Dell/DellOs10.swift

import Foundation

/// Dell EMC Networking OS10 SSH driver.
///
/// Maps to netmiko's DellOS10SSH(CiscoSSHConnection).
public final class DellOS10SSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="copy
    /// running-configuration startup-configuration").
    override public func saveConfig(
        command: String = "copy running-configuration startup-configuration",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

// MARK: - DellOS10FileTransfer

/// Dell EMC Networking OS10 SCP File Transfer driver.
///
/// Maps to netmiko's DellOS10FileTransfer(BaseFileTransfer).
///
/// OS10 wraps its Linux-underlayer commands in a "system \"...\""
/// shell-escape syntax rather than exposing them directly at the CLI,
/// and uses a real SCP client connection object (self.scp_conn) for
/// the actual transfer, distinct from the interactive CLI channel
/// used for size/existence checks.
public final class DellOS10FileTransfer: SCPHandler {

    /// A secondary directory Netmiko stores but never actually uses
    /// in any method shown in this file — set in __init__, read
    /// nowhere. Carried over faithfully as an apparent unused field
    /// in the original, same treatment as the Sophos
    /// SOPHOS_MENU_DEFAULT case — worth checking a newer Netmiko
    /// release to see if a method using this was added later.
    public let folderName = "/config"

    /// Maps to netmiko's __init__, defaulting file_system to
    /// "/home/admin".
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destFile: String,
        fileSystem: String = "/home/admin",
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

    // MARK: File Size

    /// Maps to netmiko's remote_file_size(), wrapping the underlying
    /// `ls -l` in OS10's "system" shell-escape syntax.
    override public func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        let targetFile: String
        if let remoteFile {
            targetFile = remoteFile
        } else {
            switch direction {
            case .put: targetFile = destinationFile
            case .get: targetFile = sourceFile
            }
        }

        let command = remoteCommand.isEmpty
            ? "system \"ls -l \(fileSystem)/\(targetFile)\""
            : remoteCommand
        let remoteOutput = try await connection.sendCommand(command)

        guard !remoteOutput.contains("Error opening"),
              !remoteOutput.contains("No such file or directory") else {
            throw SwiftmikoError.commandFailed("Unable to find file on remote system")
        }

        for line in remoteOutput.components(separatedBy: .newlines) where line.contains(targetFile) {
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count > 4, let size = Int(fields[4]) else { continue }
            return size
        }

        throw SwiftmikoError.commandFailed("Unable to find file on remote system")
    }

    // MARK: Space Available

    /// Maps to netmiko's remote_space_available(search_pattern=r"(\d+)
    /// bytes free"). Note the `folderName` property (not
    /// `fileSystem`) is used here — matching the Python original,
    /// which checks disk usage on a fixed "/config" path rather than
    /// wherever the actual file transfer's file_system points.
    override public func remoteSpaceAvailable(
        searchPattern: String = #"(\d+) bytes free"#
    ) async throws -> Int {
        let command = "system \"df \(folderName)\""
        let remoteOutput = try await connection.sendCommand(command)

        for line in remoteOutput.components(separatedBy: .newlines) where line.contains(folderName) {
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count >= 3, let available = Int(fields[fields.count - 3]) else { continue }
            return available
        }

        throw SwiftmikoError.commandFailed("Could not determine remote space available.")
    }

    // MARK: MD5

    /// Maps to netmiko's remote_md5(base_cmd="verify /md5").
    override public func remoteMD5(
        baseCommand: String = "verify /md5",
        remoteFile: String? = nil
    ) async throws -> String {
        let targetFile: String
        if let remoteFile {
            targetFile = remoteFile
        } else {
            switch direction {
            case .put: targetFile = destinationFile
            case .get: targetFile = sourceFile
            }
        }

        let command = "system \"md5sum \(fileSystem)/\(targetFile)\""
        let output = try await connection.sendCommand(command, readTimeout: 300)
        let hash = try SCPHandler.processMD5(output, pattern: #"(.*) (.*)"#)
        return hash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: File Existence

    /// Maps to netmiko's check_file_exists(remote_cmd="dir home").
    override public func checkFileExists(
        remoteCommand: String = "dir home"
    ) async throws -> Bool {
        switch direction {
        case .put:
            let output = try await connection.sendCommand(remoteCommand)
            let searchString = "Directory contents .*\(destinationFile)"
            return output.range(
                of: searchString,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

}
