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
// Sources/Swiftmiko/Quanta/QuantaMesh.swift

import Foundation

/// Quanta Mesh SSH driver.
///
/// Maps to netmiko's QuantaMeshSSH(CiscoSSHConnection).
public final class QuantaMeshSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read()
    ///     self.set_base_prompt()
    ///     self.set_terminal_width()
    ///     self.disable_paging("no pager")
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging(command: "no pager")
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

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="copy running-config
    /// startup-config").
    override public func saveConfig(
        command: String = "copy running-config startup-config",
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
