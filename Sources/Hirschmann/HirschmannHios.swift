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
// Sources/Swiftmiko/Hirschmann/HirschmannHios.swift

import Foundation

/// Base class for Hirschmann HiOS devices.
///
/// Maps to netmiko's HirschmannHiOSBase(CiscoBaseConnection).
///
/// Tested with Hirschmann BRS20 (Bobcat Rail Switch) running HiOS,
/// per Netmiko's own module docstring.
open class HirschmannHiOSBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="cli numlines 0")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "cli numlines 0")
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save").
    override public func saveConfig(
        command: String = "save",
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

// MARK: - HirschmannHiOSSSH

/// Hirschmann HiOS SSH driver — no differences from the base.
/// Maps to netmiko's HirschmannHiOSSSH(HirschmannHiOSBase).
public final class HirschmannHiOSSSH: HirschmannHiOSBase {}
