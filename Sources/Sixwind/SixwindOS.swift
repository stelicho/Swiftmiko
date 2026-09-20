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
// Sources/Swiftmiko/Sixwind/SixwindOS.swift

import Foundation

/// Common implementation for 6WIND OS devices (SSH only — no Telnet
/// variant in this vendor's Netmiko driver).
///
/// Maps to netmiko's SixwindOSBase(NoEnable, CiscoBaseConnection).
///
/// 6WIND uses a commit-based configuration model, similar to Viptela
/// and Cisco XR: changes are staged inside "edit running" mode and
/// only take effect after an explicit commit. There is no privilege
/// escalation step — hence NoEnable.
open class SixwindOSBase: CiscoBaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read()
    ///     self.set_base_prompt()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead()
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Paging

    /// 6WIND requires a "no-pager" flag appended to individual
    /// commands rather than a single session-wide paging toggle.
    /// That per-command mechanism isn't implemented yet — this
    /// mirrors Netmiko's own admission that it's a stub, not a true
    /// no-op the way Teldat or Zyxel's lack of paging is.
    ///
    /// Maps to netmiko's disable_paging(): "not implemented at this
    /// time", returning "".
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

    /// Sets basePrompt, used as the delimiter for stripping trailing
    /// prompt text from command output.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator="#"), which additionally trims
    /// whitespace from the detected prompt before storing it — most
    /// drivers rely on the base implementation's own trimming, but
    /// 6WIND's is applied a second time explicitly here, carried over
    /// faithfully even though it may be redundant with BaseConnection's
    /// own trimming step.
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = "#",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        basePrompt = basePrompt.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="edit running").
    @discardableResult
    override public func enterConfigMode(
        command: String = "edit running",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern=r">").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ">"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    /// Maps to netmiko's check_config_mode(check_string="#").
    override public func isInConfigMode(
        checkString: String = "#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(comment="", read_timeout=120.0).
    ///
    /// Unlike Cisco XR's commit(), which builds up a command string
    /// with various optional flags, 6WIND's commit is a fixed
    /// "commit" command sent from inside config mode, with the
    /// session explicitly dropped back out of config mode afterward
    /// regardless of outcome. Failure is detected by scanning the
    /// combined output for a fixed error marker string rather than by
    /// interpreting a device-returned exit code.
    ///
    /// Note: the `comment` parameter is accepted for interface parity
    /// with Netmiko but is unused in the underlying implementation —
    /// carried over here as-is even though it does not appear to do
    /// anything in the Python source either.
    public func commit(
        comment: String = "",
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        let errorMarker = "Failed to generate committed config"

        var output = try await enterConfigMode()
        output += try await sendCommand(
            "commit",
            readTimeout: readTimeout,
            expectString: "#",
            stripPrompt: false,
            stripCommand: false
        )
        output += try await exitConfigMode()

        if output.contains(errorMarker) {
            throw SwiftmikoError.commandFailed(
                "Commit failed with following errors:\n\n\(output)"
            )
        }
        return output
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="copy running startup",
    /// confirm=true, confirm_response="y").
    ///
    /// Note this defaults confirm to true, unlike most drivers in
    /// this vendor set which default it to false — 6WIND's save
    /// command apparently always prompts for confirmation in
    /// practice, so the default reflects that rather than requiring
    /// every caller to pass it explicitly.
    override public func saveConfig(
        command: String = "copy running startup",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

// MARK: - SixwindOSSSH

/// 6WIND OS SSH driver — no differences from the base.
/// Maps to netmiko's SixwindOSSSH(SixwindOSBase).
public final class SixwindOSSSH: SixwindOSBase {}
