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
// Sources/Swiftmiko/Linux/LinuxSsh.swift

import Foundation

/// Configurable Linux prompt terminators, matching Netmiko's
/// environment-variable overrides in spirit (renamed to the
/// Swiftmiko-branded env vars below rather than kept identical).
///
/// Maps to netmiko's module-level:
///     LINUX_PROMPT_PRI = os.getenv("NETMIKO_LINUX_PROMPT_PRI", "$")
///     LINUX_PROMPT_ALT = os.getenv("NETMIKO_LINUX_PROMPT_ALT", "#")
///     LINUX_PROMPT_ROOT = os.getenv("NETMIKO_LINUX_PROMPT_ROOT", "#")
public enum LinuxPromptDefaults {
    public static let primary: String = {
        ProcessInfo.processInfo.environment["SWIFTMIKO_LINUX_PROMPT_PRI"] ?? "$"
    }()
    public static let alternate: String = {
        ProcessInfo.processInfo.environment["SWIFTMIKO_LINUX_PROMPT_ALT"] ?? "#"
    }()
    public static let root: String = {
        ProcessInfo.processInfo.environment["SWIFTMIKO_LINUX_PROMPT_ROOT"] ?? "#"
    }()
}

/// Generic Linux SSH driver — the base every "this device is actually
/// Linux underneath" driver in Swiftmiko inherits from (Cisco APIC,
/// ZPE Nodegrid, Corelight, Cumulus, Edgecore SONiC, F5 Linux, and
/// others).
///
/// Maps to netmiko's LinuxSSH(CiscoSSHConnection).
///
/// The defining behavior: "enable mode" and "config mode" are BOTH
/// aliased to becoming root via "sudo -s" — there is no distinct
/// config-mode concept on a Linux box, only privilege level. Once
/// already logged in as root, several operations become no-ops or
/// behave differently (sendConfigSet won't try to exit "config mode"
/// since there'd be nothing to exit to; cleanup() skips the
/// exit-config-mode step entirely for root).
open class LinuxSSHConnection: CiscoSSHConnection {

    override public nonisolated var promptPattern: String {
        let priEscaped = NSRegularExpression.escapedPattern(for: LinuxPromptDefaults.primary)
        let altEscaped = NSRegularExpression.escapedPattern(for: LinuxPromptDefaults.alternate)
        return "[\(priEscaped)\(altEscaped)]"
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt()
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
    }

    // MARK: Shell Access

    /// Already in shell — hard no-op.
    /// Maps to netmiko's _enter_shell().
    /// Internal, not private — subclasses like Cisco APIC override
    /// this behavior to reach a REAL Cisco base method instead, so it
    /// needs to be reachable at module scope.
    @discardableResult
    internal func enterShell() async throws -> String {
        return ""
    }

    /// The shell IS the CLI on this platform — hard no-op.
    /// Maps to netmiko's _return_cli().
    @discardableResult
    internal func returnCLI() async throws -> String {
        return ""
    }

    // MARK: Paging

    /// Linux has no paging by default — hard no-op.
    /// Maps to netmiko's disable_paging().
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return ""
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's find_prompt(), defaulting to promptPattern
    /// when the caller doesn't supply one.
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.findPrompt(delay: delay, pattern: pattern ?? promptPattern)
    }

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=
    /// LINUX_PROMPT_PRI, alt_prompt_terminator=LINUX_PROMPT_ALT),
    /// defaulting the search pattern to promptPattern when the
    /// caller doesn't supply one.
    override public func setBasePrompt(
        primaryTerminator: String = LinuxPromptDefaults.primary,
        altTerminator: String = LinuxPromptDefaults.alternate,
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern ?? promptPattern
        )
    }

    // MARK: Config Set

    /// Send a set of configuration commands, without exiting "config
    /// mode" (becoming non-root) if the connecting user is already
    /// root.
    ///
    /// Maps to netmiko's send_config_set() — if the account
    /// connected as "root" directly (rather than escalating via
    /// sudo), there's nothing to exit back down FROM, so forcing
    /// exitConfigMode afterward would be meaningless at best and
    /// could break the session at worst.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
        readTimeout: TimeInterval? = nil,
        maxLoops: Int? = nil,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = true,
        errorPattern: String = "",
        terminator: String = "#",
        bypassCommands: String? = nil
    ) async throws -> String {
        let resolvedExit = profile.username == "root" ? false : exitConfigMode
        return try await super.sendConfigSet(commands, exitConfigMode: resolvedExit)
    }

    // MARK: Config Mode — Aliased to Root/Enable

    /// Verify root — "config mode" on Linux means being root.
    /// Maps to netmiko's check_config_mode(check_string=
    /// LINUX_PROMPT_ROOT) — forwards directly to isInEnableMode()
    /// rather than any real config-mode check.
    override public func isInConfigMode(
        checkString: String = LinuxPromptDefaults.root,
        pattern: String = ""
    ) async throws -> Bool {
        return try await isInEnableMode(checkString: checkString)
    }

    /// Attempt to become root.
    /// Maps to netmiko's config_mode(config_command="sudo -s",
    /// pattern="ssword", re_flags=re.IGNORECASE) — forwards directly
    /// to enterEnableMode(), same non-super-calling pattern seen on
    /// Yamaha and Dell Isilon.
    @discardableResult
    override public func enterConfigMode(
        command: String = "sudo -s",
        pattern: String = "ssword",

        dotAll: Bool = false
    ) async throws -> String {
        return try await enterEnableMode(
            secret: profile.secret ?? "",
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit") —
    /// forwards directly to exitEnableMode().
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return try await exitEnableMode(exitCommand: exitConfig)
    }

    // MARK: Enable Mode — Becoming Root

    /// Verify root.
    /// Maps to netmiko's check_enable_mode(check_string=
    /// LINUX_PROMPT_ROOT).
    override public func isInEnableMode(
        checkString: String = LinuxPromptDefaults.root
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Exit enable (root) mode.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    ///
    /// Re-detects the base prompt afterward specifically because
    /// Netmiko's own comment flags it: "Nature of prompt might change
    /// with the privilege deescalation" — dropping from root ("#")
    /// back to a normal user prompt ("$") is a real prompt-shape
    /// change, not just a cosmetic detail.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        output += try await readUntilPattern(pattern: exitCommand)
        output += try await readUntilPattern(pattern: promptPattern)

        // Prompt shape can change with privilege de-escalation.
        try await setBasePrompt(pattern: promptPattern)

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }

    /// Attempt to become root via "sudo -s".
    ///
    /// Maps to netmiko's enable(cmd="sudo -s", pattern="ssword",
    /// re_flags=re.IGNORECASE).
    ///
    /// A genuinely tricky detail explained by Netmiko's own comment:
    /// "Failed 'sudo -s' will put '#' in output so have to delineate
    /// further" — meaning a naive check for the root prompt character
    /// alone could false-positive even on a FAILED sudo attempt,
    /// since some failure messages happen to contain "#" too. The
    /// fix is anchoring the root-prompt pattern to end-of-line with
    /// multiline matching (`(?m:...\s*$)`), so it only matches a
    /// genuine trailing prompt, not an incidental "#" elsewhere in
    /// error text.
    ///
    /// If the password is sent but the root prompt never appears
    /// within the read timeout, this surfaces a detailed, actionable
    /// error message about supplying `secret` and sudo permissions —
    /// rather than a generic timeout.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "sudo -s",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        let failureMessage = """


        Netmiko failed to elevate privileges.

        Please ensure you pass the sudo password into ConnectHandler
        using the 'secret' argument and that the user has sudo
        permissions.

        """

        var output = ""
        if checkState, try await isInEnableMode() {
            return output
        }

        try await writeChannel(normalizeCommand(command))

        // Failed "sudo -s" can put "#" in output, so the real root
        // prompt must be anchored to end-of-line to disambiguate.
        let rootPrompt = "(?m:\(LinuxPromptDefaults.root)\\s*$)"
        let promptOrPassword = "(\(rootPrompt)|\(pattern))"
        output += try await readUntilPattern(
            pattern: promptOrPassword,
            caseInsensitive: caseInsensitive
        )

        if output.range(
            of: pattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil {
            try await writeChannel(normalizeCommand(secret))
            do {
                output += try await readUntilPattern(pattern: rootPrompt)
            } catch is SwiftmikoError {
                throw SwiftmikoError.authenticationFailed(failureMessage)
            }
        }

        // Prompt shape can change with privilege escalation.
        try await setBasePrompt(pattern: rootPrompt)

        guard try await isInEnableMode() else {
            throw SwiftmikoError.authenticationFailed(failureMessage)
        }
        return output
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit").
    ///
    /// Best-effort: exits config mode (drops root) ONLY if the
    /// connecting user isn't already root — same "root has nothing to
    /// exit to" reasoning as sendConfigSet() above — swallowing any
    /// failure, then always sends the final exit command regardless.
    override public func cleanup(command: String = "exit") async throws {
        do {
            if profile.username != "root", try await isInConfigMode() {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }

    // MARK: Save Config

    /// Not supported — a plain Linux SSH session has no notion of
    /// "saving configuration" at all.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "LinuxSSH does not support saveConfig()"
        )
    }
}

// MARK: - LinuxFileTransfer

/// Linux SCP File Transfer driver — mostly for testing purposes, per
/// Netmiko's own docstring.
///
/// Maps to netmiko's LinuxFileTransfer(CiscoFileTransfer).
public final class LinuxFileTransfer: SCPHandler {

    public static let promptPattern: String = {
        let priEscaped = NSRegularExpression.escapedPattern(for: LinuxPromptDefaults.primary)
        let altEscaped = NSRegularExpression.escapedPattern(for: LinuxPromptDefaults.alternate)
        return "[\(priEscaped)\(altEscaped)]"
    }()

    /// Maps to netmiko's __init__, defaulting file_system to
    /// "/var/tmp".
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destinationFile: String,
        fileSystem: String = "/var/tmp",
        direction: SCPTransferDirection = .put
    ) async throws {
        try await super.init(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destinationFile,
            fileSystem: fileSystem,
            direction: direction
        )
    }

    // MARK: Space / Existence / Size Checks

    /// Maps to netmiko's remote_space_available(), using
    /// promptPattern as the Unix search pattern.
    override public func remoteSpaceAvailable(
        searchPattern: String = ""
    ) async throws -> Int {
        return try await remoteSpaceAvailableUnix(searchPattern: Self.promptPattern)
    }

    /// Maps to netmiko's check_file_exists().
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        return try await checkFileExistsUnix(
            remoteCommand: remoteCommand,
            searchPattern: Self.promptPattern
        )
    }

    /// Maps to netmiko's remote_file_size().
    override public func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        return try await remoteFileSizeUnix(
            remoteCommand: remoteCommand,
            remoteFile: remoteFile,
            searchPattern: Self.promptPattern
        )
    }

    // MARK: MD5

    /// Maps to netmiko's remote_md5(base_cmd="md5sum").
    override public func remoteMD5(
        baseCommand: String = "md5sum",
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

        let command = "\(baseCommand) \(fileSystem)/\(targetFile)"
        let output = try await connection.sendCommand(command, readTimeout: 300)
        let hash = try Self.processMD5(output.trimmingCharacters(in: .whitespacesAndNewlines))
        return hash.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Maps to netmiko's static process_md5(pattern=r"^(\S+)\s+") —
    /// a thin override that just changes the default pattern and
    /// forwards to the shared base implementation.

    // MARK: Unsupported Operations

    override public func enableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("LinuxSSH does not support enableSCP")
    }

    override public func disableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("LinuxSSH does not support disableSCP")
    }
}
