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
// Sources/Swiftmiko/Arris/ArrisCER.swift

import Foundation

/// Common implementation for Arris CER platforms.
///
/// Maps to netmiko's ArrisCERBase(CiscoSSHConnection).
///
/// No session_preparation override — this driver relies entirely on
/// CiscoSSHConnection's own default session prep. Worth confirming
/// during testing that those defaults (paging, prompt detection) are
/// actually appropriate for Arris CER out of the box, since unlike
/// most drivers in this vendor set, nothing here customizes that
/// sequence at all.
open class ArrisCERBase: CiscoSSHConnection {

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="configure").
    ///
    /// Note the bare "configure" rather than the more common
    /// "configure terminal" seen on most Cisco-family devices.
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory").
    override public func saveConfig(
        command: String = "write memory",
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

// MARK: - ArrisCERSSH

/// Arris CER SSH driver — no differences from the base.
/// Maps to netmiko's ArrisCERSSH(ArrisCERBase).
public final class ArrisCERSSH: ArrisCERBase {}
