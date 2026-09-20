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
// Sources/Swiftmiko/Endace/Endace.swift

import Foundation

/// Endace network monitoring appliance SSH driver.
///
/// Maps to netmiko's EndaceSSH(CiscoSSHConnection).
public final class EndaceSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read()
    ///     self.set_base_prompt()
    ///     self.set_terminal_width()
    ///     self.disable_paging(command="no cli session paging enable")
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging(command: "no cli session paging enable")
    }

    // MARK: Enable Mode

    /// Maps to netmiko's enable(cmd="enable", pattern="",
    /// re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "",
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

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="(config) #").
    /// Same literal-space-before-# quirk as Silver Peak and Aruba OS.
    override public func isInConfigMode(
        checkString: String = "(config) #",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Enter configuration mode, handling a device warning that can
    /// appear before access is granted.
    ///
    /// Maps to netmiko's config_mode(config_command="conf t").
    ///
    /// This is a fully custom implementation rather than a forward to
    /// super — Endace can respond to "conf t" with a warning asking
    /// whether you really want to enter configuration mode anyway
    /// (likely guarding against concurrent-session conflicts), which
    /// must be answered "YES" before the config prompt actually
    /// appears. If the check for config mode still fails after
    /// answering, this throws rather than returning a
    /// misleadingly-successful empty result.
    @discardableResult
    override public func enterConfigMode(
        command: String = "conf t",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        var output = ""
        guard try await !isInConfigMode() else { return output }

        output += try await sendCommandTiming(
            command,
            stripPrompt: false,
            stripCommand: false
        )

        if output.contains("to enter configuration mode anyway") {
            output += try await sendCommandTiming(
                "YES",
                stripPrompt: false,
                stripCommand: false
            )
        }

        guard try await isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to enter configuration mode")
        }
        return output
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern="#").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="configuration write").
    ///
    /// Unusually explicit about privilege state before saving: rather
    /// than assuming the caller is already enabled and in config
    /// mode, this actively re-enters both enable mode AND config mode
    /// immediately before issuing the save command — presumably
    /// because "configuration write" specifically requires being
    /// inside config mode to run at all, unlike most save commands
    /// which run from plain enable mode.
    override public func saveConfig(
        command: String = "configuration write",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")
        _ = try await enterConfigMode()
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
