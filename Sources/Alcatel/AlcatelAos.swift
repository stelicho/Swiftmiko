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
// Sources/Swiftmiko/Alcatel/AlcatelAos.swift

import Foundation

/// Alcatel-Lucent Enterprise AOS SSH driver (AOS6 and AOS8).
///
/// Maps to netmiko's AlcatelAosSSH(NoEnable, NoConfig,
/// CiscoSSHConnection).
///
/// No privilege escalation and no configuration mode on this
/// platform — hence NoEnable + NoConfig.
public final class AlcatelAosSSH: CiscoSSHConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///
    /// Comment carried over from Netmiko: the prompt can technically
    /// be anything, but AOS's own best practice is to end it with
    /// ">" or "#", which is why that's the pattern used here rather
    /// than something more permissive.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory
    /// flash-synchro").
    ///
    /// "flash-synchro" additionally syncs the config to the backup
    /// flash partition on redundant AOS8 chassis — a single "write
    /// memory" alone would only persist to primary storage.
    override public func saveConfig(
        command: String = "write memory flash-synchro",
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
