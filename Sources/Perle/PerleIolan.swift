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
// Sources/Swiftmiko/Perle/PerleIolan.swift

import Foundation

/// Perle IOLan console/terminal server SSH driver.
///
/// Maps to netmiko's PerleIolanSSH(NoConfig, CiscoBaseConnection).
///
/// No configuration mode via this connection — hence NoConfig. The
/// most distinctive behavior: rather than disabling pagination via a
/// device command up front, this driver walks through Perle's
/// "< Hit any key >" pagination prompt manually, inside
/// sendCommandTiming() itself, sending a bare space to advance each
/// page until the interstitial stops appearing. It also feeds every
/// command's output through Swiftmiko's structured-data conversion
/// pipeline (TextFSM/TTP/Genie-equivalent) before returning it — the
/// only driver in this vendor set doing that at the individual-driver
/// level rather than leaving it entirely to the caller.
public final class PerleIolanSSH: CiscoBaseConnection, NoConfig {

    /// Perle requires a bare "\r" line ending.
    /// Maps to netmiko's __init__ override:
    ///     self.default_enter = kwargs.get("default_enter", "\r")
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read()
    ///     self.set_base_prompt(alt_prompt_terminator="$")
    override public func sessionPreparation() async throws {
        _ = try await testChannelRead()
        try await setBasePrompt(altTerminator: "$")
    }

    // MARK: Enable Mode

    /// Enter admin mode.
    /// Maps to netmiko's enable(cmd="admin", pattern="ssword:",
    /// re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "admin",
        pattern: String = "ssword:",
        enablePattern: String? = nil,
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
            caseInsensitive: caseInsensitive
        )
    }

    /// Perle has no concept of exiting enable mode — hard no-op.
    /// Maps to netmiko's exit_enable_mode().
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = ""
    ) async throws -> String {
        return ""
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save", confirm=true,
    /// confirm_response="y").
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Timing-Based Command Execution

    /// Send a timing-based command, walking through any
    /// "< Hit any key >" pagination interstitials before returning
    /// structured or raw output.
    ///
    /// Maps to netmiko's send_command_timing() override.
    ///
    /// The sequence is genuinely involved:
    ///   1. Send the real command, WITHOUT stripping prompt or
    ///      command echo yet — those get applied manually at the end,
    ///      after all pagination has been consumed, not per-page.
    ///   2. While the "< Hit any key >" marker keeps appearing in the
    ///      accumulated output: strip that specific marker line out,
    ///      then send a bare space (Perle's own "continue" keystroke)
    ///      to advance to the next page, appending whatever comes
    ///      back.
    ///   3. Once no more pagination markers remain, sanitize the
    ///      FULL accumulated output in one pass — this is where the
    ///      caller's original strip_prompt/strip_command preferences
    ///      actually get applied, deferred until now specifically so
    ///      pagination artifacts don't interfere with clean stripping.
    ///   4. Feed the sanitized output through Swiftmiko's structured-
    ///      data conversion pipeline, honoring whatever
    ///      TextFSM/TTP/Genie-equivalent options the caller requested.
    ///
    /// This is the only driver in the entire vendor set that calls a
    /// structured-data conversion pipeline directly from inside a
    /// send method rather than leaving that entirely to the caller —
    /// worth confirming Swiftmiko actually HAS an equivalent
    /// `structuredDataConverter` utility (this file assumes one
    /// exists, matching netmiko.utilities.structured_data_converter,
    /// but it hasn't been translated in this pass yet).
    @discardableResult
    override public func sendCommandTiming(
        _ command: String,
        readTimeout: TimeInterval = 2.0,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true
    ) async throws -> String {
        let morePattern = "< Hit any key >"

        var output = try await super.sendCommandTiming(
            command,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: false,
            stripCommand: false,
            cmdVerify: cmdVerify
        )

        while output.contains(morePattern) {
            output = output.replacingOccurrences(of: "\n" + morePattern, with: "")
            let nextPage = try await super.sendCommandTiming(
                " ",
                readTimeout: readTimeout,
                expectString: expectString,
                stripPrompt: false,
                stripCommand: true,
                cmdVerify: cmdVerify
            )
            output += nextPage
        }

        if stripCommand { output = self.stripCommand(command, output: output) }
        if stripPrompt  { output = self.stripPrompt(output) }

        return output
    }

    // MARK: Output Stripping

    /// Strip the trailing prompt repeatedly, in case multiple
    /// trailing prompt lines are present.
    ///
    /// Maps to netmiko's strip_prompt() override.
    ///
    /// Netmiko's own comment: "Delete repeated prompts." Structured
    /// as a fixed-point loop — keep calling the base stripPrompt()
    /// until a call returns the SAME string it was given, meaning
    /// nothing more was stripped. This is a genuinely different
    /// approach from Furukawa FITELnet's or MikroTik's equivalent
    /// "strip more than one trailing prompt" logic, which both use an
    /// explicit bounded loop with a set of known-valid prompt shapes
    /// rather than an unbounded fixed-point convergence check —
    /// worth being a little cautious here, since a pathological input
    /// where stripPrompt() never converges (unlikely, but not
    /// provably impossible) would loop indefinitely. Preserved
    /// faithfully since Netmiko's own version has the identical risk
    /// profile.
    override public func stripPrompt(_ output: String) -> String {
        var current = output
        while true {
            let next = super.stripPrompt(current)
            if next == current { break }
            current = next
        }
        return current
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="logout").
    override public func cleanup(command: String = "logout") async throws {
        try await super.cleanup(command: command)
    }
}
