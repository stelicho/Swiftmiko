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
// Sources/Swiftmiko/Arista/Arista.swift

import Foundation

/// Common implementation for Arista EOS devices (both SSH and Telnet).
///
/// Maps to netmiko's AristaBase(CiscoSSHConnection).
open class AristaBase: CiscoSSHConnection {

    override public nonisolated var promptPattern: String { #"[$>#]"# }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// The terminal-width command is wrapped in its own error
    /// handling — some Arista platforms or EOS versions don't support
    /// it, and Netmiko explicitly continues past that failure rather
    /// than treating it as fatal to the whole session. Both
    /// disablePaging and the width command wait for a specific
    /// confirmation phrase in the device's response rather than just
    /// the bare command echo, which is unusual precision for a
    /// session-prep step.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: promptPattern)

        do {
            let widthCommand = "terminal width 511"
            try await setTerminalWidth(command: widthCommand, pattern: "Width set to")
        } catch is SwiftmikoError {
            // Continue on if setting 'terminal width' fails — some
            // Arista platforms don't support this command, and it
            // isn't essential to a working session.
        }

        try await disablePaging(
            command: "terminal length 0",
            cmdVerify: false,
            pattern: "Pagination disabled"
        )
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Find the current prompt, defaulting to Arista's own broader
    /// prompt pattern rather than a plain search.
    ///
    /// Maps to netmiko's find_prompt().
    ///
    /// Arista devices sometimes duplicate the command echo if the
    /// device falls behind processing input:
    ///
    ///     arista9-napalm#
    ///     show version | json
    ///     arista9-napalm#show version | json
    ///
    /// Using the full terminating pattern (rather than a loose match)
    /// makes it less likely the read gets confused by that
    /// duplication and returns a stale or partial prompt.
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.findPrompt(
            delay: delay,
            pattern: pattern ?? promptPattern
        )
    }

    // MARK: Enable Mode

    /// Maps to netmiko's enable(cmd="enable", pattern="ssword",
    /// enable_pattern=r"\#", re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = #"#"#,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        return try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive,
            defaultUsername: defaultUsername
        )
    }

    // MARK: Config Mode

    /// Checks if the device is in configuration mode.
    ///
    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern=r"[>\#]").
    ///
    /// Does NOT call super — Arista's multi-supervisor chassis
    /// prompts embed a supervisor slot indicator directly in the
    /// prompt string:
    ///
    ///     loc1-core01(s1)#
    ///     loc1-core01(s2)#
    ///
    /// Left in place, "(s1)" or "(s2)" would sit between the hostname
    /// and the ")#" check string being searched for, breaking a naive
    /// substring match. Both variants are stripped before comparing.
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = #"[>#]"#
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)
        var output = try await readUntilPattern(pattern: pattern)
        output = output.replacingOccurrences(of: "(s1)", with: "")
        output = output.replacingOccurrences(of: "(s2)", with: "")
        return output.contains(checkString)
    }

    /// Enter configuration mode.
    ///
    /// Maps to netmiko's config_mode(config_command="configure
    /// terminal").
    ///
    /// Forces DOTALL matching (so "." matches newlines too) and, when
    /// the caller doesn't supply an explicit success pattern, builds
    /// one dynamically: the truncated base prompt followed by
    /// anything, followed by ")#". This forces Arista to read all the
    /// way through to the prompt on the line *after* the command
    /// echo, rather than stopping early on an intermediate ")#" that
    /// might appear mid-output before the real prompt line arrives.
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure terminal",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        let useDotAll = dotAll || pattern.isEmpty
        let checkString = NSRegularExpression.escapedPattern(for: ")#")

        var resolvedPattern = pattern
        if resolvedPattern.isEmpty {
            let truncatedPrompt = NSRegularExpression.escapedPattern(
                for: String(basePrompt.prefix(16))
            )
            resolvedPattern = "\(truncatedPrompt).*\(checkString)"
        }

        return try await super.enterConfigMode(
            command: command,
            pattern: resolvedPattern,
            dotAll: useDotAll
        )
    }

    // MARK: Shell Access

    /// Enter the underlying Bourne shell.
    /// Maps to netmiko's _enter_shell().
    /// Internal, not private — AristaFileTransfer does not currently
    /// use this, but it mirrors the module-internal visibility of the
    /// Python leading-underscore convention seen on other drivers.
    @discardableResult
    internal func enterShell() async throws -> String {
        return try await sendCommand("bash", expectString: #"[\$#]"#)
    }

    /// Return to the Arista CLI from the Bourne shell.
    /// Maps to netmiko's _return_cli().
    @discardableResult
    internal func returnCLI() async throws -> String {
        return try await sendCommand("exit", expectString: "[#>]")
    }
}

// MARK: - AristaSSH

/// Arista EOS SSH driver — no differences from the base.
/// Maps to netmiko's AristaSSH(AristaBase).
public final class AristaSSH: AristaBase {}

// MARK: - AristaTelnet

/// Arista EOS Telnet driver.
/// Maps to netmiko's AristaTelnet(AristaBase). Overrides the default
/// line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class AristaTelnet: AristaBase {

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

// MARK: - AristaFileTransfer

/// Arista SCP File Transfer driver.
///
/// Maps to netmiko's AristaFileTransfer(CiscoFileTransfer).
///
/// Uses Unix-flavored helper implementations for space/existence
/// checks (like ZpeNodegridFileTransfer did) rather than the
/// IOS-style "dir" command parsing most Cisco file transfer classes
/// use — Arista's underlying filesystem behaves more like a Linux
/// mount than a traditional Cisco flash filesystem.
public final class AristaFileTransfer: SCPHandler {

    /// Maps to netmiko's class-level prompt_pattern override, used
    /// specifically as the search pattern for space-availability
    /// checks below.
    public static let promptPattern = #"[$>#]"#

    /// Maps to netmiko's __init__, which defaults file_system to
    /// "/mnt/flash" rather than the generic BaseFileTransfer default.
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destFile: String,
        fileSystem: String = "/mnt/flash",
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

    // MARK: Space / Existence Checks

    /// Return space available on the remote device.
    /// Maps to netmiko's remote_space_available(), which overrides
    /// the search pattern with the class-level prompt_pattern before
    /// delegating to the generic Unix implementation.
    override public func remoteSpaceAvailable(
        searchPattern: String = ""
    ) async throws -> Int {
        return try await remoteSpaceAvailableUnix(
            searchPattern: Self.promptPattern
        )
    }

    /// Check if the destination file already exists.
    /// Maps to netmiko's check_file_exists().
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        return try await checkFileExistsUnix(remoteCommand: remoteCommand)
    }

    /// Get the file size of the remote file.
    /// Maps to netmiko's remote_file_size().
    override public func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        return try await remoteFileSizeUnix(
            remoteCommand: remoteCommand,
            remoteFile: remoteFile
        )
    }

    // MARK: MD5

    /// Calculate the remote MD5 hash.
    ///
    /// Maps to netmiko's remote_md5(base_cmd="verify /md5").
    ///
    /// Note the "file:" prefix in the command — Arista's verify
    /// command expects a URI-style path (file:/mnt/flash/filename)
    /// rather than the bare colon-separated path most Cisco IOS-style
    /// devices use.
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

        let remoteCommand = "\(baseCommand) file:\(fileSystem)/\(targetFile)"
        let output = try await connection.sendCommand(
            remoteCommand,
            readTimeout: 600
        )
        return try Self.processMD5(output)
    }

    // MARK: Unsupported Operations

    override public func enableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented(
            "Arista does not support enableSCP"
        )
    }

    override public func disableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented(
            "Arista does not support disableSCP"
        )
    }
}
