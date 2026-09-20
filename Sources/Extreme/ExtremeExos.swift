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
// Sources/Swiftmiko/Extreme/ExtremeExos.swift

import Foundation

/// Extreme EXOS SSH driver base (designed for EXOS >= 15.0).
///
/// Maps to netmiko's ExtremeExosBase(NoConfig, CiscoSSHConnection).
///
/// No configuration mode via this connection — hence NoConfig. The
/// defining quirk of this platform: EXOS attaches an auto-incrementing
/// command counter directly to the prompt itself
/// ("testhost.1 #", "testhost.2 #", ...), and prefixes it with "* "
/// when there are unsaved configuration changes. That means the
/// prompt is LITERALLY DIFFERENT after every single command — this
/// driver has to re-detect the base prompt before every sendCommand
/// call, not just once during session prep.
open class ExtremeExosBase: CiscoSSHConnection, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>\#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="disable clipaging")
    ///     self.send_command_timing("disable cli prompting")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: #"[>#]"#)
        try await setBasePrompt()
        try await disablePaging(command: "disable clipaging")
        _ = try await sendCommandTiming("disable cli prompting")
    }

    // MARK: Prompt Detection

    /// Detect the base prompt, stripping EXOS's incrementing counter
    /// and unsaved-changes marker.
    ///
    /// Maps to netmiko's set_base_prompt() override.
    ///
    /// EXOS prompts look like "testhost.1 #", "testhost.2 #", or
    /// "* testhost.4 #" (leading asterisk + space when unsaved
    /// changes exist). The regex captures everything before the
    /// final ".NNN" counter, discarding any leading "*"/whitespace
    /// and the trailing period-plus-digits entirely — leaving just
    /// "testhost" as the stable, reusable basePrompt.
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

        let captureGroupPattern = #"[\*\s]*(.*)\.\d+"#
        if let match = basePrompt.range(of: captureGroupPattern, options: .regularExpression) {
            // Extract just the captured group — re-run a targeted
            // capture since Foundation's range(of:) doesn't expose
            // capture groups directly the way NSRegularExpression does.
            let nsString = basePrompt as NSString
            let regex = try? NSRegularExpression(pattern: captureGroupPattern)
            if let regexMatch = regex?.firstMatch(
                in: basePrompt,
                range: NSRange(location: 0, length: nsString.length)
            ), regexMatch.numberOfRanges > 1 {
                basePrompt = nsString.substring(with: regexMatch.range(at: 1))
            }
            _ = match // silence unused-variable warning from the initial range(of:) check
        }
    }

    // MARK: Command Execution

    /// Send a command, refreshing basePrompt immediately beforehand
    /// since EXOS's prompt changes with every command.
    ///
    /// Maps to netmiko's send_command() override.
    ///
    /// Forces autoFindPrompt off — EXOS's own prompt-refresh dance
    /// here replaces whatever generic auto-detection the base
    /// sendCommand would otherwise attempt, since that generic
    /// detection doesn't know about EXOS's counter-and-asterisk
    /// scheme.
    @discardableResult
    override public func sendCommand(
        _ command: String,
        readTimeout: TimeInterval? = nil,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true,
        autoFindPrompt: Bool = false
    ) async throws -> String {
        try await setBasePrompt()
        return try await super.sendCommand(
            command,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            autoFindPrompt: autoFindPrompt
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save configuration primary").
    override public func saveConfig(
        command: String = "save configuration primary",
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

/// Extreme EXOS SSH driver — no differences from the base.
/// Maps to netmiko's ExtremeExosSSH(ExtremeExosBase).
public final class ExtremeExosSSH: ExtremeExosBase {}

/// Extreme EXOS Telnet driver.
/// Maps to netmiko's ExtremeExosTelnet(ExtremeExosBase). Overrides
/// the default line ending to "\r\n" unless the caller's profile
/// already specifies one.
public final class ExtremeExosTelnet: ExtremeExosBase {

    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r\n"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }
}

// MARK: - ExtremeExosFileTransfer

/// Extreme EXOS SCP File Transfer driver.
///
/// Maps to netmiko's ExtremeExosFileTransfer(BaseFileTransfer).
///
/// The second file transfer class in this vendor set (after
/// ArubaOsFileTransfer) with NO MD5 support at all — every hash
/// method throws. Verification falls back to file-size comparison,
/// same pattern as Aruba OS.
public final class ExtremeExosFileTransfer: SCPHandler {

    /// Maps to netmiko's __init__, defaulting file_system to
    /// "/usr/local/cfg" and hash_supported to false.
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destFile: String,
        fileSystem: String = "/usr/local/cfg",
        direction: SCPTransferDirection = .put,
        socketTimeout: TimeInterval = 10.0
    ) async throws {
        try await super.init(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destFile,
            fileSystem: fileSystem,
            direction: direction,
            socketTimeout: socketTimeout,
            hashSupported: false
        )
    }

    // MARK: Space Available

    /// Maps to netmiko's remote_space_available(search_pattern=r"(\d+)\s+\d+%$").
    override public func remoteSpaceAvailable(
        searchPattern: String = #"(\d+)\s+\d+%$"#
    ) async throws -> Int {
        let output = try await connection.sendCommand("ls \(fileSystem)")

        guard !output.contains("Invalid pathname"),
              !output.contains("No such file or directory") else {
            throw SwiftmikoError.commandFailed("Invalid file_system: \(fileSystem)")
        }

        guard let match = output.range(of: searchPattern, options: .regularExpression) else {
            throw SwiftmikoError.commandFailed(
                "pattern: \(searchPattern) not detected in output:\n\n\(output)"
            )
        }

        let regex = try? NSRegularExpression(pattern: searchPattern)
        let nsOutput = output as NSString
        guard let regexMatch = regex?.firstMatch(
            in: output, range: NSRange(location: 0, length: nsOutput.length)
        ), regexMatch.numberOfRanges > 1,
        let size = Int(nsOutput.substring(with: regexMatch.range(at: 1))) else {
            throw SwiftmikoError.commandFailed(
                "pattern: \(searchPattern) not detected in output:\n\n\(output)"
            )
        }
        _ = match
        return size
    }

    /// Maps to netmiko's verify_space_available(search_pattern=r"(\d+)\s+\d+%$").
    override public func verifySpaceAvailable(
        searchPattern: String = #"(\d+)\s+\d+%$"#
    ) async throws -> Bool {
        return try await super.verifySpaceAvailable(searchPattern: searchPattern)
    }

    // MARK: File Existence

    /// Maps to netmiko's check_file_exists().
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        switch direction {
        case .put:
            let command = remoteCommand.isEmpty
                ? "ls \(fileSystem)/\(destinationFile)"
                : remoteCommand
            let output = try await connection.sendCommand(command)

            if output.contains("No such file or directory") || output.contains("Invalid pathname") {
                return false
            } else if output.contains(destinationFile) {
                return true
            } else {
                throw SwiftmikoError.commandFailed("Unexpected output from check_file_exists")
            }
        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

    // MARK: File Size

    /// Maps to netmiko's remote_file_size().
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
            ? "ls \(fileSystem)/\(targetFile)"
            : remoteCommand
        let output = try await connection.sendCommand(command)

        let escapedName = NSRegularExpression.escapedPattern(for: targetFile)
        let pattern = ".*(\(escapedName)).*"

        guard let matchLine = output.components(separatedBy: .newlines)
            .first(where: { $0.range(of: pattern, options: .regularExpression) != nil }) else {
            throw SwiftmikoError.commandFailed(
                "Unable to parse 'ls' output in remoteFileSize method"
            )
        }

        guard !output.contains("No such file or directory"), !output.contains("Invalid pathname") else {
            throw SwiftmikoError.commandFailed("Unable to find file on remote system")
        }

        let fields = matchLine.split(separator: " ").map(String.init)
        guard fields.count > 4, let size = Int(fields[4]) else {
            throw SwiftmikoError.commandFailed(
                "Unable to parse 'ls' output in remoteFileSize method"
            )
        }
        return size
    }

    // MARK: MD5 — Unsupported

    public func fileMD5(fileName: String, addNewline: Bool = false) throws -> String {
        throw SwiftmikoError.notImplemented("EXOS does not support an MD5-hash operation.")
    }
    override public func compareMD5() async throws -> Bool {
        throw SwiftmikoError.notImplemented("EXOS does not support an MD5-hash operation.")
    }
    override public func remoteMD5(baseCommand: String = "", remoteFile: String? = nil) async throws -> String {
        throw SwiftmikoError.notImplemented("EXOS does not support an MD5-hash operation.")
    }

    // MARK: SCP Enable/Disable — Unsupported

    /// EXOS always has SCP enabled — there is no toggle.
    override public func enableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented(
            "EXOS does not support an enable SCP operation. SCP is always enabled."
        )
    }
    override public func disableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("EXOS does not support a disable SCP operation.")
    }

    // MARK: Verification

    /// Maps to netmiko's verify_file() — same file-size-comparison
    /// fallback pattern as ArubaOsFileTransfer, for the same reason
    /// (no MD5 support on this platform).
    override public func verifyFile() async throws -> Bool {
        switch direction {
        case .put:
            let localSize = try FileManager.default
                .attributesOfItem(atPath: sourceFile)[.size] as? Int ?? -1
            let remoteSize = try await remoteFileSize(remoteFile: destinationFile)
            return localSize == remoteSize
        case .get:
            let remoteSize = try await remoteFileSize(remoteFile: sourceFile)
            let localSize = try FileManager.default
                .attributesOfItem(atPath: destinationFile)[.size] as? Int ?? -1
            return remoteSize == localSize
        }
    }
}
