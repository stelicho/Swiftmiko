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
// Sources/Swiftmiko/Centec/CentecOS.swift

import Foundation

/// Common implementation for Centec OS devices (both SSH and Telnet).
///
/// Maps to netmiko's CentecOSBase(CiscoBaseConnection).
open class CentecOSBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging()
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write").
    override public func saveConfig(
        command: String = "write",
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

// MARK: - CentecOSSSH

/// Centec OS SSH driver — no differences from the base.
/// Maps to netmiko's CentecOSSSH(CentecOSBase).
public final class CentecOSSSH: CentecOSBase {}

// MARK: - CentecOSTelnet

/// Centec OS Telnet driver — no differences from the base.
/// Maps to netmiko's CentecOSTelnet(CentecOSBase).
public final class CentecOSTelnet: CentecOSBase {}
