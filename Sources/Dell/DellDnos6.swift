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
// Sources/Swiftmiko/Dell/DellDnos6.swift

import Foundation

/// Common implementation for Dell N2/3/4000 series switches running
/// DNOS6.
///
/// Maps to netmiko's DellDNOS6Base(DellPowerConnectBase).
open class DellDNOS6Base: DellPowerConnectBase {

    /// Maps to netmiko's session_preparation() — note this fully
    /// replaces the parent's version rather than extending it; DNOS6
    /// uses a single paging command ("terminal length 0") rather than
    /// PowerConnect's dual-command approach, and adds a terminal
    /// width step the parent doesn't have.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await setTerminalWidth()
        try await disablePaging(command: "terminal length 0")
    }

    /// Maps to netmiko's save_config(cmd="copy running-config
    /// startup-config", confirm=true, confirm_response="y").
    override public func saveConfig(
        command: String = "copy running-config startup-config",
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

/// Dell DNOS6 SSH driver — no differences from the base.
/// Maps to netmiko's DellDNOS6SSH(DellDNOS6Base).
public final class DellDNOS6SSH: DellDNOS6Base {}

/// Dell DNOS6 Telnet driver — no differences from the base.
/// Maps to netmiko's DellDNOS6Telnet(DellDNOS6Base).
public final class DellDNOS6Telnet: DellDNOS6Base {}
