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
// Sources/Swiftmiko/Fujitsu/FujitsuSir.swift

import Foundation

/// Common implementation for Fujitsu Si-R devices.
///
/// Maps to netmiko's FujitsuSirBase(BaseConnection).
///
/// "Enable mode" on this platform means Fujitsu's own "admin" mode —
/// same shape as Yamaha's Administrator mode (cmd="admin"/
/// "administrator", pattern="Password").
open class FujitsuSirBase: BaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="terminal pager disable")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "terminal pager disable")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Enter "admin" mode.
    /// Maps to netmiko's enable(cmd="admin", pattern=r"Password",
    /// re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "admin",
        pattern: String = "Password",
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

    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="(config)#").
    override public func isInConfigMode(
        checkString: String = "(config)#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="configure").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="end",
    /// pattern="#").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = "#"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Persist the running configuration to flash memory.
    ///
    /// Maps to netmiko's save_config(cmd="commit", read_timeout=120.0).
    ///
    /// Sends the command directly rather than going through the base
    /// saveConfig machinery — same bypass pattern as Juniper
    /// ScreenOS's saveConfig(), presumably because "commit" here
    /// needs no confirm/confirmResponse handling.
    public func saveConfig(
        command: String = "commit",
        confirm: Bool = false,
        confirmResponse: String = "",
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        return try await sendCommand(
            command,
            readTimeout: readTimeout,
            stripPrompt: false,
            stripCommand: false
        )
    }
}

// MARK: - FujitsuSirSSH

/// Fujitsu Si-R SSH driver — no differences from the base.
/// Maps to netmiko's FujitsuSirSSH(FujitsuSirBase).
public final class FujitsuSirSSH: FujitsuSirBase {}
