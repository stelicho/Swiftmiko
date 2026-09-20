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
// Sources/Swiftmiko/Extreme/ExtremeSlx.swift

import Foundation

/// Extreme SLX SSH driver.
///
/// Maps to netmiko's ExtremeSlxSSH(NoEnable, CiscoSSHConnection).
///
/// Structurally identical to ExtremeNosSSH — same session prep, same
/// settle-delay login handler, same save command. If this and
/// ExtremeNosSSH ever need to diverge, that's the signal to factor
/// out a shared internal base; for now, kept as separate faithful
/// translations matching Netmiko's own separate files.
public final class ExtremeSlxSSH: CiscoSSHConnection, NoEnable {

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
    }

    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let resolvedDelay = selectDelayFactor(delay)
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(1.0 * resolvedDelay * 1_000_000_000))
    }

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
