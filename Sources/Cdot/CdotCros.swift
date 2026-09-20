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
// Sources/Swiftmiko/Cdot/CdotCros.swift

import Foundation

/// CDOT CROS SSH driver.
///
/// CDOT = Centre for Development of Telematics, India.
/// CROS = CDOT Router OS.
///
/// Maps to netmiko's CdotCrosSSH(NoEnable, CiscoBaseConnection).
///
/// No privilege escalation on this platform — hence NoEnable. Like
/// Aruba and Silver Peak, CROS auto-completes commands on a space
/// character, which desynchronizes command echo from what was
/// actually sent. Unlike those two drivers, CROS exposes an explicit
/// device command to disable that behavior outright
/// ("complete-on-space false"), so this driver fixes the problem at
/// the source during session prep rather than disabling echo
/// verification globally as a workaround.
public final class CdotCrosSSH: CiscoBaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[#\$]")
    ///     self.set_base_prompt()
    ///     self._disable_complete_on_space()
    ///     self.set_terminal_width(command="screen-width 511", pattern=r"screen.width 511")
    ///     self.disable_paging(command="screen-length 0")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: #"[#\$]"#)
        try await setBasePrompt()
        _ = try await disableCompleteOnSpace()
        try await setTerminalWidth(
            command: "screen-width 511",
            pattern: "screen.width 511"
        )
        try await disablePaging(command: "screen-length 0")
    }

    // MARK: Config Set

    /// Send a set of configuration commands.
    ///
    /// Maps to netmiko's send_config_set(), which forwards to the
    /// base implementation with exitConfigMode defaulted to false —
    /// CROS requires the session to remain in config mode after
    /// sending a set of commands. This mirrors Cisco XR's identical
    /// requirement and comment almost verbatim.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = false,
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
        return try await super.sendConfigSet(
            commands,
            exitConfigMode: exitConfigMode,
            readTimeout: readTimeout,
            maxLoops: maxLoops,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            configModeCommand: configModeCommand,
            cmdVerify: cmdVerify,
            enterConfigMode: enterConfigMode,
            errorPattern: errorPattern,
            terminator: terminator,
            bypassCommands: bypassCommands
        )
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern=r"[#\$]").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = #"[#\$]"#
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="config").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(comment="", read_timeout=120.0,
    /// and_quit=true).
    ///
    /// Builds the commit command string with an optional quoted
    /// comment, enters config mode, sends the commit, and checks the
    /// output against two possible success markers — "Commit
    /// complete" for an actual change, or "No modifications to
    /// commit" when nothing had actually changed since the last
    /// commit (which is still a success, not a failure). Optionally
    /// exits config mode afterward, controlled by `andQuit`.
    ///
    /// A comment containing a literal double-quote is rejected before
    /// ever reaching the device — building the command string with an
    /// unescaped quote inside a quoted argument would corrupt the
    /// command itself.
    @discardableResult
    public func commit(
        comment: String = "",
        readTimeout: TimeInterval = 120.0,
        andQuit: Bool = true
    ) async throws -> String {
        var commandString = "commit"
        let commitMarkers = ["Commit complete", "No modifications to commit"]

        if !comment.isEmpty {
            guard !comment.contains("\"") else {
                throw SwiftmikoError.invalidArgument(
                    "Invalid comment contains double quote"
                )
            }
            commandString += " comment \"\(comment)\""
        }

        var output = try await enterConfigMode()
        output += try await sendCommand(
            commandString,
            readTimeout: readTimeout,
            stripPrompt: false,
            stripCommand: true
        )

        guard commitMarkers.contains(where: { output.contains($0) }) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }

        if andQuit {
            _ = try await exitConfigMode()
        }
        return output
    }

    // MARK: Complete-on-Space

    /// Disable CROS's auto-complete-on-space behavior.
    ///
    /// Maps to netmiko's _disable_complete_on_space().
    ///
    /// CROS tries to auto-complete commands whenever a space
    /// character is typed — fine for an interactive human typing
    /// commands, but disastrous for automation, since the command
    /// echoed back by the device no longer matches what was actually
    /// sent once auto-completion has silently expanded it. This sends
    /// a single fixed command to turn that behavior off entirely,
    /// with brief settle delays around the write, mirroring Netmiko's
    /// direct write_channel/read_channel pair rather than going
    /// through sendCommand's full echo/prompt-matching machinery —
    /// appropriate here since command auto-completion is exactly the
    /// failure mode sendCommand's echo verification would otherwise
    /// trip over.
    @discardableResult
    private func disableCompleteOnSpace() async throws -> String {
        let delay = selectDelayFactor(0)
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))

        let command = "complete-on-space false"
        try await writeChannel(normalizeCommand(command))

        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        return try await readChannel()
    }
}
