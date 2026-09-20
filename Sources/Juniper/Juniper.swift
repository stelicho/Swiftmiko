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
// Sources/Swiftmiko/Juniper/Juniper.swift

import Foundation

/// Common implementation for Juniper Networks devices running JunOS.
///
/// Maps to netmiko's JuniperBase(NoEnable, BaseConnection).
///
/// No privilege escalation on this platform — hence NoEnable. JunOS
/// has a genuine shell/CLI duality (this device is FreeBSD-derived
/// underneath, similar in spirit to Cisco APIC's Linux heritage), and
/// this driver automatically detects and switches into CLI mode
/// during session prep if the connection happened to land at the raw
/// shell instead.
open class JuniperBase: BaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     pattern = r"[%>$#]"
    ///     self._test_channel_read(pattern=pattern)
    ///     self.enter_cli_mode()
    ///     cmd = "set cli screen-width 511"
    ///     self.set_terminal_width(command=cmd, pattern=r"Screen width set to")
    ///     self.disable_paging(command="set cli complete-on-space off", ...)
    ///     self.disable_paging(command="set cli screen-length 0", ...)
    ///     self.set_base_prompt()
    ///
    /// Netmiko's own comment is worth preserving: "Overloading
    /// disable_paging which is confusing" — disablePaging() is called
    /// TWICE here for two functionally unrelated purposes (turning
    /// off auto-complete-on-space, and turning off actual pagination).
    /// It's a slight misuse of the method's name, inherited as-is
    /// rather than split into a separate method, since JunOS drivers
    /// elsewhere in the ecosystem may depend on disablePaging being
    /// the method that's overridden to intercept both behaviors.
    override public func sessionPreparation() async throws {
        let pattern = "[%>$#]"
        try await testChannelRead(pattern: pattern)
        try await enterCLIMode()

        let widthCommand = "set cli screen-width 511"
        try await setTerminalWidth(command: widthCommand, pattern: "Screen width set to")

        try await disablePaging(
            command: "set cli complete-on-space off",
            pattern: "Disabling complete-on-space"
        )
        try await disablePaging(
            command: "set cli screen-length 0",
            pattern: "Screen length set to"
        )
        try await setBasePrompt()
    }

    // MARK: Shell / CLI Mode Detection

    /// Enter the Bourne shell from the JunOS CLI.
    /// Maps to netmiko's _enter_shell().
    @discardableResult
    internal func enterShell() async throws -> String {
        return try await sendCommand("start shell sh", expectString: #"[\$#]"#)
    }

    /// Return to the JunOS CLI from the underlying shell.
    /// Maps to netmiko's _return_cli().
    @discardableResult
    internal func returnCLI() async throws -> String {
        return try await sendCommand("exit", expectString: "[#>]")
    }

    /// Determine whether the session is currently at a shell prompt
    /// or the JunOS CLI prompt.
    ///
    /// Maps to netmiko's _determine_mode(data="").
    ///
    /// If no data is supplied, sends a bare return and reads what
    /// comes back first. Distinguishes a shell prompt (root@, a bare
    /// "%", or a "$") from a CLI prompt (">" or "#") — throws if
    /// neither pattern is recognized, since that indicates the device
    /// is in some unexpected state this driver doesn't know how to
    /// interpret.
    internal enum JuniperMode {
        case shell
        case cli
    }

    internal func determineMode(data: String = "") async throws -> JuniperMode {
        var resolvedData = data
        if resolvedData.isEmpty {
            try await writeChannel(profile.returnCharacter)
            resolvedData = try await readUntilPattern(pattern: "[%>$#]", timeout: 10.0)
        }

        let shellPattern = #"(?:root@|%|\$)"#
        if resolvedData.range(of: shellPattern, options: .regularExpression) != nil {
            return .shell
        } else if resolvedData.contains(">") || resolvedData.contains("#") {
            return .cli
        } else {
            throw SwiftmikoError.unexpectedPrompt(
                "Unexpected data returned for prompt: \(resolvedData)"
            )
        }
    }

    /// Detect a shell prompt and switch into the JunOS CLI if
    /// necessary.
    ///
    /// Maps to netmiko's enter_cli_mode().
    ///
    /// Only actually sends "cli" if BOTH at a shell prompt AND that
    /// prompt specifically looks like a root shell or a bare "%" —
    /// a "$" alone (a non-root user shell) is detected as .shell by
    /// determineMode() but does NOT trigger switching into cli here,
    /// matching Netmiko's more conservative double-check rather than
    /// acting on the broader shell-pattern match alone.
    internal func enterCLIMode() async throws {
        let mode = try await determineMode()
        guard mode == .shell else { return }

        let shellPattern = #"(?:root@|%|\$)"#
        try await writeChannel(profile.returnCharacter)
        let currentPrompt = try await readUntilPattern(pattern: shellPattern, timeout: 10.0)

        let isRootPrompt = currentPrompt.range(of: "root@", options: .regularExpression) != nil
        let isBarePercent = currentPrompt.trimmingCharacters(in: .whitespaces) == "%"

        if isRootPrompt || isBarePercent {
            try await writeChannel("cli" + profile.returnCharacter)
            _ = try await readUntilPattern(pattern: "[>#]", timeout: 10.0)
        }
    }

    // MARK: Config Mode

    /// Checks if the device is in configuration mode.
    ///
    /// Maps to netmiko's check_config_mode(check_string="]",
    /// pattern=r"(?m:[>#] $)").
    ///
    /// Uses multiline matching. Netmiko's own comment explains why
    /// this can't be a simple substring check: JunOS uses "#" as a
    /// generic MESSAGE indicator even OUTSIDE config mode — for
    /// example, during a "commit confirmed" countdown. Checking for
    /// "]" (part of JunOS's "[edit]" context marker) rather than "#"
    /// avoids a false positive from that unrelated use of "#".
    override public func isInConfigMode(
        checkString: String = "]",
        pattern: String = "(?m:[>#] $)"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Enter configuration mode.
    ///
    /// Maps to netmiko's config_mode(config_command="configure",
    /// pattern=r"(?s:Entering configuration mode.*\].*#)").
    ///
    /// Uses DOTALL matching (re.DOTALL / "?s") so the pattern can
    /// span the multi-line banner JunOS prints when entering config
    /// mode, ending on the "[edit]" context marker's closing bracket
    /// followed eventually by the "#" prompt.
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = #"(?s:Entering configuration mode.*\].*#)"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Exit configuration mode, handling uncommitted-changes
    /// confirmation.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="exit
    /// configuration-mode").
    ///
    /// Same discard-uncommitted-changes-by-answering-yes pattern
    /// seen on Viptela and Allied Telesis — "yes" here means "yes,
    /// exit anyway and discard," not "yes, save first."
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit configuration-mode",
        pattern: String = ""
    ) async throws -> String {
        var output = ""
        guard try await isInConfigMode() else { return output }

        let confirmMessage = "Exit with uncommitted changes"
        let expectPattern = "(?:>|\(confirmMessage))"

        output = try await sendCommand(
            exitConfig,
            expectString: expectPattern,
            stripPrompt: false,
            stripCommand: false
        )

        if output.contains(confirmMessage) {
            output += try await sendCommand(
                "yes",
                expectString: ">",
                stripPrompt: false,
                stripCommand: false
            )
        }

        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }
        return output
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(confirm=false, confirm_delay=None,
    /// check=false, comment="", and_quit=false, read_timeout=120.0).
    ///
    /// The richest commit-family method in this entire vendor set —
    /// four mutually-exclusive argument combinations are validated up
    /// front before building the command string:
    ///
    ///   check alone           → "commit check"
    ///   confirm (+ delay)     → "commit confirmed [delay]"
    ///   default               → "commit"
    ///   any + comment         → appends ` comment "..."`
    ///   any + andQuit         → appends " and-quit"
    ///
    /// check combined with confirm/confirmDelay/comment is invalid
    /// (JunOS's "commit check" is a dry-run validation only — it
    /// makes no sense combined with confirmation or a comment on an
    /// actual commit), and confirmDelay without confirm is
    /// meaningless (nothing to attach a rollback delay to).
    ///
    /// The expected termination pattern accounts for the possibility
    /// that the commit itself changes the hostname (and therefore the
    /// prompt), or that and_quit drops the session out of config mode
    /// entirely as a side effect of a successful commit.
    @discardableResult
    public func commit(
        confirm: Bool = false,
        confirmDelay: Int? = nil,
        check: Bool = false,
        comment: String = "",
        andQuit: Bool = false,
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        guard !(check && (confirm || confirmDelay != nil || !comment.isEmpty)) else {
            throw SwiftmikoError.invalidArgument(
                "Invalid arguments supplied with commit check"
            )
        }
        guard !(confirmDelay != nil && !confirm) else {
            throw SwiftmikoError.invalidArgument(
                "Invalid arguments supplied to commit method both confirm and check"
            )
        }

        var commandString = "commit"
        var commitMarker = "commit complete"

        if check {
            commandString = "commit check"
            commitMarker = "configuration check succeeds"
        } else if confirm {
            if let confirmDelay {
                commandString = "commit confirmed \(confirmDelay)"
            } else {
                commandString = "commit confirmed"
            }
            commitMarker = "commit confirmed will be automatically rolled back in"
        }

        if !comment.isEmpty {
            guard !comment.contains("\"") else {
                throw SwiftmikoError.invalidArgument(
                    "Invalid comment contains double quote"
                )
            }
            commandString += " comment \"\(comment)\""
        }

        if andQuit {
            commandString += " and-quit"
        }

        var output = try await enterConfigMode()

        // Hostname might change on commit; and-quit might exit config
        // mode as a side effect — the expected termination pattern
        // has to tolerate either the (possibly now-stale) base prompt
        // or a fresh ">"/"#" prompt appearing instead.
        let escapedPrompt = NSRegularExpression.escapedPattern(for: basePrompt)
        let expectString = "(?:\(escapedPrompt)|[>#]\\s*$)"

        output += try await sendCommand(
            commandString,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: false,
            stripCommand: false
        )

        guard output.contains(commitMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }
        return output
    }

    // MARK: Output Stripping

    /// Strip the trailing prompt, then also strip JunOS-specific
    /// context markers.
    ///
    /// Maps to netmiko's strip_prompt() override, which chains into
    /// strip_context_items().
    override public func stripPrompt(_ output: String) -> String {
        let base = super.stripPrompt(output)
        return stripContextItems(base)
    }

    /// Strip JunOS's configuration-context and chassis-context
    /// marker lines from output.
    ///
    /// Maps to netmiko's strip_context_items().
    ///
    /// JunOS appends lines like "[edit]" (current config context) or
    /// "{master:0}" / "{backup:1}" (which Routing Engine is active on
    /// a dual-RE chassis) to command output. These aren't part of the
    /// actual command result and are stripped if they appear as the
    /// LAST line of output — mirroring the same "only strip if it's
    /// the trailing line" caution used for the base prompt itself.
    internal func stripContextItems(_ output: String) -> String {
        let stringsToStrip = [
            #"\[edit.*\]"#,
            #"\{master:?.*\}"#,
            #"\{backup:?.*\}"#,
            #"\{line.*\}"#,
            #"\{primary.*\}"#,
            #"\{secondary.*\}"#,
        ]

        var lines = output.components(separatedBy: responseReturn)
        guard let last = lines.last else { return output }

        for pattern in stringsToStrip {
            if last.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                lines.removeLast()
                return lines.joined(separator: responseReturn)
            }
        }
        return output
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit").
    ///
    /// Best-effort: exits config mode if currently in it, swallowing
    /// any failure, then always sends the final exit command
    /// regardless — same shape as Check Point Gaia and Casa CMTS's
    /// cleanup implementations.
    override public func cleanup(command: String = "exit") async throws {
        do {
            if try await isInConfigMode() {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }
}

// MARK: - JuniperSSH

/// Juniper JunOS SSH driver — no differences from the base.
/// Maps to netmiko's JuniperSSH(JuniperBase).
public final class JuniperSSH: JuniperBase {}

// MARK: - JuniperTelnet

/// Juniper JunOS Telnet driver.
/// Maps to netmiko's JuniperTelnet(JuniperBase). Overrides the
/// default line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class JuniperTelnet: JuniperBase {

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

// MARK: - JuniperFileTransfer

/// Juniper SCP File Transfer driver.
///
/// Maps to netmiko's JuniperFileTransfer(BaseFileTransfer).
///
/// Uses the same Unix-flavored helper implementations as
/// ZpeNodegridFileTransfer and AristaFileTransfer for
/// space/existence/size checks — JunOS's underlying FreeBSD shell
/// behaves like a standard Unix filesystem for these purposes.
public final class JuniperFileTransfer: SCPHandler {

    /// Maps to netmiko's __init__, defaulting file_system to
    /// "/var/tmp".
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destFile: String,
        fileSystem: String = "/var/tmp",
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

    // MARK: Space / Existence / Size Checks

    /// Maps to netmiko's remote_space_available(), overriding the
    /// search pattern to JunOS's multi-character prompt set before
    /// delegating to the generic Unix implementation.
    override public func remoteSpaceAvailable(
        searchPattern: String = ""
    ) async throws -> Int {
        return try await remoteSpaceAvailableUnix(searchPattern: "[%>$#]")
    }

    /// Maps to netmiko's check_file_exists().
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        return try await checkFileExistsUnix(remoteCommand: remoteCommand)
    }

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

    /// Maps to netmiko's remote_md5(base_cmd="file checksum md5") —
    /// JunOS's own command for computing a file hash, distinct from
    /// the generic Unix "md5sum" used on Linux-derived platforms.
    override public func remoteMD5(
        baseCommand: String = "file checksum md5",
        remoteFile: String? = nil
    ) async throws -> String {
        return try await super.remoteMD5(baseCommand: baseCommand, remoteFile: remoteFile)
    }

    // MARK: Unsupported Operations

    override public func enableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("Juniper does not support enableSCP")
    }

    override public func disableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented("Juniper does not support disableSCP")
    }
}
