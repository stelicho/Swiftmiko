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
// Sources/Swiftmiko/Coriant/CoriantSSH.swift

import Foundation

/// Coriant SSH driver.
///
/// Maps to netmiko's CoriantSSH(NoEnable, NoConfig, CiscoSSHConnection).
///
/// No privilege escalation and no configuration mode — hence
/// NoEnable + NoConfig. Prompt terminator scheme (":" primary, ">"
/// alternate, 2.0s delay) is identical to Accedian's — likely a
/// shared heritage or similar underlying platform vendor.
public final class CoriantSSH: CiscoSSHConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>:]")
    ///     self.set_base_prompt()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>:]")
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=":",
    /// alt_prompt_terminator=">", delay_factor=2.0).
    override public func setBasePrompt(
        primaryTerminator: String = ":",
        altTerminator: String = ">",
        delay: TimeInterval = 2.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Coriant does not support saveConfig()"
        )
    }
}
