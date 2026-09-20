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
// Sources/Swiftmiko/Hillstone/HillstoneStoneos.swift

import Foundation

/// Common implementation for Hillstone StoneOS firewall devices.
///
/// Maps to netmiko's HillstoneStoneosBase(NoEnable, CiscoBaseConnection).
///
/// No privilege escalation on this platform — hence NoEnable.
open class HillstoneStoneosBase: CiscoBaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"#")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="terminal length 0")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await disablePaging(command: "terminal length 0")
    }

    // MARK: Config Mode

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

    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern="#").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save all", confirm=true,
    /// confirm_response="y").
    override public func saveConfig(
        command: String = "save all",
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

// MARK: - HillstoneStoneosSSH

/// Hillstone StoneOS SSH driver — no differences from the base.
/// Maps to netmiko's HillstoneStoneosSSH(HillstoneStoneosBase).
public final class HillstoneStoneosSSH: HillstoneStoneosBase {}
