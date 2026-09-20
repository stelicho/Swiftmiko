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
// Sources/Swiftmiko/Extreme/ExtremeTierra.swift

import Foundation

/// Extreme TierraOS SSH driver.
///
/// Maps to netmiko's ExtremeTierraSSH(NoEnable, CiscoSSHConnection).
///
/// Same settle-delay login handler as NOS/SLX, but with its own
/// paging command and save command/confirmation defaults.
public final class ExtremeTierraSSH: CiscoSSHConnection, NoEnable {

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging(command: "terminal length 0")
    }

    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let resolvedDelay = selectDelayFactor(delay)
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(1.0 * resolvedDelay * 1_000_000_000))
    }

    /// Maps to netmiko's save_config(cmd="copy run
    /// flash://config-file/startup-config", confirm=false).
    /// Note confirm defaults to FALSE here, unlike NOS/SLX's true —
    /// a genuine difference, not a copy-paste inconsistency.
    override public func saveConfig(
        command: String = "copy run flash://config-file/startup-config",
        confirm: Bool = false,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
