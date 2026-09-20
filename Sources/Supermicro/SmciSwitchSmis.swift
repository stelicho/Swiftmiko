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
// Sources/Swiftmiko/Smci/SmciSwitchSmis.swift

import Foundation

/// Common implementation for Super Micro Computer (SMCI) SMIS switches
/// (both SSH and Telnet).
///
/// Maps to netmiko's SmciSwitchSmisBase(NoEnable, CiscoBaseConnection).
///
/// SMCI has no separate enable step (NoEnable), and unusually,
/// paging and terminal width are both set from inside configuration
/// mode rather than at the exec prompt — most Cisco-family drivers
/// do this before ever entering config mode. session_preparation()
/// enters config mode, makes both changes, then exits again.
open class SmciSwitchSmisBase: CiscoBaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.config_mode()
    ///     self.disable_paging(command="set cli pagination off")
    ///     self.set_terminal_width(command="terminal width 511")
    ///     self.exit_config_mode()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterConfigMode()
        try await disablePaging(command: "set cli pagination off")
        try await setTerminalWidth(command: "terminal width 511")
        try await exitConfigMode()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    ///
    /// NoEnable already supplies isInEnableMode() returning true
    /// unconditionally, but SMCI's actual prompt does distinguish "#"
    /// from ">" the same as any Cisco-family device — this override
    /// preserves that real check rather than relying on NoEnable's
    /// always-true default.
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write startup-config").
    override public func saveConfig(
        command: String = "write startup-config",
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

// MARK: - SmciSwitchSmisSSH

/// SMCI SMIS SSH driver — no differences from the base.
/// Maps to netmiko's SmciSwitchSmisSSH(SmciSwitchSmisBase).
public final class SmciSwitchSmisSSH: SmciSwitchSmisBase {}

// MARK: - SmciSwitchSmisTelnet

/// SMCI SMIS Telnet driver — no differences from the base.
/// Maps to netmiko's SmciSwitchSmisTelnet(SmciSwitchSmisBase).
public final class SmciSwitchSmisTelnet: SmciSwitchSmisBase {}
