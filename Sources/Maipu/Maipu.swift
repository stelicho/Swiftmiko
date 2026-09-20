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
// Sources/Swiftmiko/Maipu/Maipu.swift

import Foundation

/// Common implementation for MAIPU devices (both SSH and Telnet).
///
/// Maps to netmiko's MaipuBase(CiscoBaseConnection).
open class MaipuBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.disable_paging(command="more off")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "more off")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
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

// MARK: - MaipuSSH

/// MAIPU SSH driver — no differences from the base.
/// Maps to netmiko's MaipuSSH(MaipuBase).
public final class MaipuSSH: MaipuBase {}

// MARK: - MaipuTelnet

/// MAIPU Telnet driver — no differences from the base.
/// Maps to netmiko's MaipuTelnet(MaipuBase).
public final class MaipuTelnet: MaipuBase {}
