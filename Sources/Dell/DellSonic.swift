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
// Sources/Swiftmiko/Dell/DellSonic.swift

import Foundation

/// Dell EMC PowerSwitch platforms running Enterprise SONiC (Dell's
/// own distribution) SSH driver.
///
/// Maps to netmiko's DellSonicSSH(NoEnable, CiscoSSHConnection).
///
/// Same dual-shell architecture as Asterfusion's AsterNOS — SONiC is
/// genuinely Linux underneath, and this device exposes both the
/// "sonic-cli" network-style shell and the underlying Linux shell,
/// with session_preparation() always entering the cli automatically.
public final class DellSonicSSH: CiscoSSHConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>$#]")
    ///     self._enter_cli()
    ///     self.disable_paging()
    ///     self.set_base_prompt(alt_prompt_terminator="$")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>$#]")
        _ = try await enterCLI()
        try await disablePaging()
        try await setBasePrompt(altTerminator: "$")
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="configure
    /// terminal", pattern=r"\#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure terminal",
        pattern: String = #"#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory").
    override public func saveConfig(
        command: String = "write memory",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Shell / CLI Switching

    /// Enter sonic-cli from the underlying Linux shell.
    /// Maps to netmiko's _enter_cli().
    /// Internal, not private — DellSonicFileTransfer needs to call
    /// this directly to hop back into the CLI after dropping to the
    /// shell for filesystem operations.
    @discardableResult
    internal func enterCLI() async throws -> String {
        return try await sendCommand("sonic-cli", expectString: #"#"#)
    }

    /// Return to the underlying Linux shell from sonic-cli.
    /// Maps to netmiko's _return_shell().
    @discardableResult
    internal func returnShell() async throws -> String {
        return try await sendCommand("exit", expectString: #"\$"#)
    }
}

// MARK: - DellSonicFileTransfer

/// Dell EMC Networking SONiC SCP File Transfer driver.
///
/// Maps to netmiko's DellSonicFileTransfer(BaseFileTransfer).
///
/// Unlike DellOS10FileTransfer's "system \"...\"" shell-escape
/// syntax, this class drops all the way back to the raw Linux shell
/// for every filesystem operation, then explicitly re-enters
/// sonic-cli afterward — a full context switch rather than a
/// one-command escape hatch. Every method here follows the same
/// pattern: returnShell() → run the real Linux command → enterCLI().
public final class DellSonicFileTransfer: SCPHandler {

    /// Typed reference to the owning connection, giving access to
    /// enterCLI()/returnShell() that a plain BaseConnection reference
    /// wouldn't expose.
    /// Maps to netmiko's self.ssh_ctl_chan: DellSonicSSH type
    /// annotation.
    private var sonicConnection: DellSonicSSH {
        connection as! DellSonicSSH
    }

    /// Maps to netmiko's __init__, defaulting file_system to
    /// "/home/admin".
    public init(
        connection: DellSonicSSH,
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

    /// Maps to netmiko's remote_file_size() — drops to the Linux
    /// shell, runs a real `ls -l`, then re-enters sonic-cli
    /// regardless of the outcome. Note this doesn't use a defer for
    /// the re-entry the way ZpeNodegrid's remoteMD5 did — matching
    /// Netmiko's own structure exactly, where enterCLI() is only
    /// called on the success path, before the final error check. If
    /// the command itself throws, the session would be left sitting
    /// in the Linux shell rather than sonic-cli — carried over as-is
    /// rather than "fixed" with a defer, since that would be a
    /// behavioral change beyond a straight translation.
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

        _ = try await sonicConnection.returnShell()
        let command = remoteCommand.isEmpty
            ? "ls -l \(fileSystem)/\(targetFile)"
            : remoteCommand
        let remoteOutput = try await connection.sendCommand(command)

        var fileSize: Int?
        for line in remoteOutput.components(separatedBy: .newlines) where line.contains(targetFile) {
            let fields = line.split(separator: " ").map(String.init)
            if fields.count > 4 { fileSize = Int(fields[4]) }
            break
        }

        _ = try await sonicConnection.enterCLI()

        guard !remoteOutput.contains("No such file or directory") else {
            throw SwiftmikoError.commandFailed("Unable to find file on remote system")
        }
        guard let size = fileSize else {
            throw SwiftmikoError.commandFailed("Unable to parse remote file size")
        }
        return size
    }

    // MARK: Space Available

    /// Maps to netmiko's remote_space_available(search_pattern=r"Available").
    override public func remoteSpaceAvailable(
        searchPattern: String = "Available"
    ) async throws -> Int {
        _ = try await sonicConnection.returnShell()
        let command = "df \(fileSystem)"
        let remoteOutput = try await connection.sendCommand(command)

        var spaceAvailable: Int?
        for line in remoteOutput.components(separatedBy: .newlines) where line.contains("root-overlay") {
            let fields = line.split(separator: " ").map(String.init)
            if fields.count > 3 { spaceAvailable = Int(fields[3]) }
            break
        }

        _ = try await sonicConnection.enterCLI()

        guard let available = spaceAvailable else {
            throw SwiftmikoError.commandFailed("Could not determine remote space available.")
        }
        return available
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

        _ = try await sonicConnection.returnShell()
        let command = "md5sum \(fileSystem)/\(targetFile)"
        let output = try await connection.sendCommand(command, readTimeout: 300)
        let hash = try SCPHandler.processMD5(output, pattern: #"(.*) (.*)"#)
        _ = try await sonicConnection.enterCLI()

        return hash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: File Existence

    /// Maps to netmiko's check_file_exists(remote_cmd="dir home:/").
    override public func checkFileExists(
        remoteCommand: String = "dir home:/"
    ) async throws -> Bool {
        switch direction {
        case .put:
            let output = try await connection.sendCommand(remoteCommand)
            return output.range(
                of: destinationFile,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

}
