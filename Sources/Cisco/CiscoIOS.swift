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
//  CiscoIOS.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//

// Sources/Swiftmiko/Cisco/CiscoIOS.swift

import Foundation
import Logging

// MARK: - CiscoIOSBase

/// Common implementation for all Cisco IOS variants (SSH, Telnet, Serial).
///
/// Maps to netmiko's CiscoIosBase(CiscoBaseConnection).
///
/// Three IOS-specific behaviors live here:
///   1. Terminal width forced to 511 columns during session prep
///   2. Base prompt truncated to 16 chars (IOS abbreviates hostname
///      at 20 chars inside config mode — 16 gives a reliable margin)
///   3. Config mode detected by ")#" suffix, saved with "write mem"
open class CiscoIOSBase: CiscoBaseConnection {

    // MARK: Prompt Pattern

    /// IOS uses '#' in privileged exec and config mode, '>' in user exec.
    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Prepare the session after SSH authentication succeeds.
    ///
    /// Maps to netmiko's:
    ///     cmd = "terminal width 511"
    ///     self.set_terminal_width(command=cmd, pattern=cmd)
    ///     self.disable_paging()
    ///     self.set_base_prompt()
    ///
    /// Order matters here: width must be set before paging is disabled,
    /// and both must complete before we try to detect the prompt.
    override public func sessionPreparation() async throws {
        let widthCmd = "terminal width 511"
        try await setTerminalWidth(command: widthCmd, pattern: widthCmd)
        try await disablePaging()
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Detect and store the base prompt, truncated to 16 characters.
    ///
    /// Why 16? IOS abbreviates the hostname at 20 chars inside config mode.
    /// A device named "very-long-router-name" shows its prompt as:
    ///
    ///     very-long-router-na(config)#
    ///
    /// If we stored the full hostname as basePrompt we would never find it
    /// in config mode output. prefix(16) → "very-long-router" appears as
    /// a substring in both exec and config mode prompts reliably.
    ///
    /// Maps to netmiko's: self.base_prompt = base_prompt[:16]
    ///
    /// Note: Swift's prefix(_:) is safe on any String length,
    /// unlike Python's slice which silently handles short strings too.
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        basePrompt = String(basePrompt.prefix(16))
        logger.debug("IOS base prompt (truncated to 16): '\(basePrompt)'")
    }

    // MARK: Config Mode

    /// Check whether the device is in configuration mode.
    ///
    /// IOS config mode appends "(config)#" or sub-mode variants like
    /// "(config-if)#", "(config-router)#" to the hostname.
    /// The ")#" check_string distinguishes these from plain exec "#".
    ///
    /// Maps to netmiko's:
    ///     def check_config_mode(self, check_string=")#", pattern=r"[>#]"):
    ///         return super().check_config_mode(...)
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

    /// Save running-config to NVRAM.
    ///
    /// IOS uses "write mem" (equivalent to "copy running-config startup-config"
    /// but shorter and universally supported across IOS versions).
    @discardableResult
    override public func saveConfig(
        command: String = "write mem",
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

// MARK: - Leaf Types

/// Cisco IOS SSH driver.
/// Maps to netmiko's CiscoIosSSH(CiscoIosBase).
/// `final` prevents further subclassing — use CiscoIOSBase if you need to extend.
public final class CiscoIOSSSH: CiscoIOSBase {}

/// Cisco IOS Telnet driver.
/// Maps to netmiko's CiscoIosTelnet(CiscoIosBase).
/// Telnet uses \r\n — set returnCharacter: "\r\n" in ConnectionProfile.
public final class CiscoIOSTelnet: CiscoIOSBase {}

/// Cisco IOS Serial (console) driver.
/// Maps to netmiko's CiscoIosSerial(CiscoIosBase).
/// Used for direct console connections, typically through a terminal server.
public final class CiscoIOSSerial: CiscoIOSBase {}

// MARK: - File Transfer

/// Cisco IOS SCP File Transfer driver.
/// Maps to netmiko's CiscoIosFileTransfer(CiscoFileTransfer).
/// All behavior inherited from SCPHandler — this exists for type identity
/// so callers can distinguish IOS transfers from other vendors.
public class CiscoIOSFileTransfer: SCPHandler {}

// MARK: - InLineTransfer

/// Transfer a file to Cisco IOS using TCL instead of SCP.
///
/// Maps to netmiko's InLineTransfer(CiscoIosFileTransfer).
///
/// Use this when `ip scp server enable` is not configured on the device.
/// Instead of opening a second SCP channel, it enters the device's
/// built-in tclsh and uses TCL's `puts [open ...]` to write the file
/// contents directly into flash — byte by byte through the existing
/// SSH session.
///
/// Constraints (same as Netmiko):
///   - Put direction only (no get)
///   - File contents must not contain literal curly braces { }
///   - File contents must not contain trailing backslashes on any line
///   - No progress callback (paste is opaque)
///
/// Usage:
///     let xfer = try await InLineTransfer(
///         connection: conn,
///         sourceFile: "/tmp/acl-update.txt",
///         destinationFile: "flash:acl-update.txt"
///     )
///     try await xfer.transfer()
///     let ok = try await xfer.verify()
public final class InLineTransfer: CiscoIOSFileTransfer {

    // MARK: Properties

    /// The source file path (if reading from disk), distinct from SCPHandler.sourceFile
    public let inlineSourceFile: String?
    public let sourceConfig: String?

    /// Read timeout scales with file size, mirroring Netmiko's if/elif chain.
    /// Expressed as a Swift switch on a range pattern — cleaner than chained ifs.
    private var transferReadTimeout: TimeInterval {
        switch fileSize {
        case 7500...: return 600   // 10 min for very large configs
        case 2500...: return 300   // 5 min for medium configs
        default:      return 100   // ~90s for small configs
        }
    }

    /// Initial sleep before polling for TCL prompt.
    /// Mirrors Netmiko's sleep_time calculation exactly.
    private var initialSleep: TimeInterval {
        switch fileSize {
        case 7500...: return 25
        case 2500...: return 12
        default:      return 4
        }
    }

    // MARK: Init

    public init(
        connection: BaseConnection,
        sourceFile: String? = nil,
        sourceConfig: String? = nil,
        destinationFile: String,
        fileSystem: String? = nil
    ) async throws {

        // Guard the same invariants Netmiko checks in __init__
        guard !destinationFile.isEmpty else {
            throw SwiftmikoError.invalidArgument(
                "destinationFile must be specified for InLineTransfer"
            )
        }
        guard !(sourceFile != nil && sourceConfig != nil) else {
            throw SwiftmikoError.invalidArgument(
                "Specify either sourceFile or sourceConfig, not both"
            )
        }
        guard sourceFile != nil || sourceConfig != nil else {
            throw SwiftmikoError.invalidArgument(
                "Either sourceFile or sourceConfig must be provided"
            )
        }

        self.inlineSourceFile = sourceFile
        self.sourceConfig = sourceConfig

        // Autodetect file system if not specified.
        // Maps to: self.file_system = self.ssh_ctl_chan._autodetect_fs()
        let resolvedFileSystem: String
        if let fs = fileSystem {
            resolvedFileSystem = fs
        } else {
            resolvedFileSystem = try await connection.autodetectFileSystem()
        }

        try await super.init(
            connection: connection,
            sourceFile: sourceFile ?? "",
            destinationFile: destinationFile,
            fileSystem: resolvedFileSystem,
            direction: .put
        )
    }

    // MARK: Public API

    /// Run the complete transfer sequence.
    ///
    /// Netmiko splits this across establish_scp_conn / put_file / close_scp_chan.
    /// In Swift we unify into one call since TCL mode is not a persistent channel.
    /// The `defer` guarantees exit from TCL mode even if putFile throws.
    public func transfer() async throws {
        _ = try await enterTCLMode()
        defer {
            // Best-effort cleanup — don't mask the original error if putFile threw
            Task { try? await exitTCLMode() }
        }
        try await putFileInline()
    }

    /// Verify transfer integrity by comparing MD5 hashes.
    ///
    /// Runs `verify /md5 flash:filename` on the device and compares
    /// the result to the hash computed at init time.
    public func verify() async throws -> Bool {
        let output = try await connection.sendCommand(
            "verify /md5 \(fileSystem)\(destinationFile)"
        )
        // IOS outputs: "verify /md5 flash:file.txt = abc123def456..."
        guard let match = output.firstMatch(of: #/=\s*([a-fA-F0-9]{32})/#) else {
            throw SwiftmikoError.commandFailed(
                "Could not parse MD5 hash from device output: \(output)"
            )
        }
        let remoteHash = String(match.output.1).lowercased()
        connection.logger.debug("Source MD5:  \(sourceMD5 ?? "nil")")
        connection.logger.debug("Remote MD5:  \(remoteHash)")
        return remoteHash == (sourceMD5 ?? "")
    }

    // MARK: TCL Mode

    /// Enter tclsh on the device.
    ///
    /// Maps to netmiko's _enter_tcl_mode().
    private func enterTCLMode() async throws -> String {
        let failurePatterns = [
            #"Translating "tclsh""#,
            "% Unknown command",
            "% Bad IP address"
        ]

        let output = try await connection.sendCommand(
            "tclsh",
            expectString: #"\(tcl\)#"#,
            stripPrompt: false,
            stripCommand: false
        )

        for pattern in failurePatterns {
            if output.contains(pattern) {
                throw SwiftmikoError.commandFailed(
                    "Device does not support tclsh — cannot use InLineTransfer: \(output)"
                )
            }
        }
        return output
    }

    /// Exit tclsh and return to the normal IOS prompt.
    ///
    /// Maps to netmiko's _exit_tcl_mode().
    @discardableResult
    private func exitTCLMode() async throws -> String {
        try await connection.writeChannel("\r")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        var output = try await connection.readChannel()
        if output.contains("(tcl)") {
            try await connection.writeChannel("tclquit\r")
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        output += try await connection.readChannel()
        return output
    }

    // MARK: File Write

    /// Paste the file into the device using TCL's puts command.
    ///
    /// Maps to netmiko's put_file().
    private func putFileInline() async throws {
        let tclOpen = #"puts [open "\#(fileSystem)\#(destinationFile)" w+] {"#
        let tclClose = "}"

        let rawContent: String
        if let path = inlineSourceFile {
            rawContent = try String(contentsOfFile: path, encoding: .utf8)
        } else if let config = sourceConfig {
            rawContent = config
        } else {
            throw SwiftmikoError.invalidArgument("No source content available")
        }

        let tclContent = try InLineTransfer.tclRationalize(rawContent)

        // Clear stale data before starting the paste
        try await connection.clearBuffer()

        // Write: open command → file contents → closing brace
        try await connection.writeChannel(tclOpen)
        try await Task.sleep(nanoseconds: 250_000_000) // 0.25s settle
        try await connection.writeChannel(tclContent)
        try await connection.writeChannel(tclClose + "\r")

        // Wait for IOS to absorb the paste before polling
        try await Task.sleep(nanoseconds: UInt64(initialSleep * 1_000_000_000))

        // Wait for TCL prompt — confirms puts completed
        _ = try await connection.readUntilPattern(
            pattern: #"\(tcl\).*$"#,
            timeout: transferReadTimeout
        )

        // Flush the file to disk by quitting tclsh
        try await connection.writeChannel("tclquit\r")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Wait for tclquit echo + base prompt = file is written
        let donePattern = "tclquit.*\(connection.basePrompt).*$"
        _ = try await connection.readUntilPattern(
            pattern: donePattern,
            timeout: transferReadTimeout
        )
    }

    // MARK: Static Helpers

    /// Prepare file content for TCL transfer.
    ///
    /// Maps to netmiko's _tcl_newline_rationalize().
    private static func tclRationalize(_ input: String) throws -> String {
        let result = input.replacingOccurrences(of: "\n", with: "\r")

        if result.range(of: "[{}]", options: .regularExpression) != nil {
            throw SwiftmikoError.invalidArgument(
                "File content contains curly braces — escape them before using InLineTransfer"
            )
        }
        if result.range(of: #"\\$"#, options: .regularExpression) != nil {
            throw SwiftmikoError.invalidArgument(
                "File content has a trailing backslash — TCL treats this as line continuation"
            )
        }
        return result
    }

    // MARK: Unsupported Operations

    override public func getFile() async throws {
        throw SwiftmikoError.notImplemented(
            "InLineTransfer only supports put direction"
        )
    }
    override public func enableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("Not applicable to InLineTransfer")
    }
    override public func disableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("Not applicable to InLineTransfer")
    }
}
