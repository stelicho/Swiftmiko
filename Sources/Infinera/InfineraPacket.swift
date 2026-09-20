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
// Sources/Swiftmiko/Infinera/InfineraPacket.swift

import Foundation

/// Common implementation for Infinera Packet devices (both SSH and
/// Telnet).
///
/// Maps to netmiko's InfineraBase(CiscoBaseConnection).
open class InfineraBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.disable_paging("terminal more off")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "terminal more off")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }
}

// MARK: - InfineraPacketSSH

/// Infinera Packet SSH driver — no differences from the base.
/// Maps to netmiko's InfineraPacketSSH(InfineraBase).
public final class InfineraPacketSSH: InfineraBase {}

// MARK: - InfineraPacketTelnet

/// Infinera Packet Telnet driver — no differences from the base.
/// Maps to netmiko's InfineraPacketTelnet(InfineraBase).
public final class InfineraPacketTelnet: InfineraBase {}
