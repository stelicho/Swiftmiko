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
// Sources/Swiftmiko/Apc/ApcAos.swift

import Foundation

/// APC AOS SSH driver.
///
/// Maps to netmiko's ApcAosSSH(BaseConnection, NoEnable, NoConfig).
///
/// No privilege escalation and no configuration mode — hence
/// NoEnable + NoConfig. Inherits directly from BaseConnection with no
/// Cisco-family lineage at all, similar to SmartOpticsDWDM.
public final class ApcAosSSH: BaseConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r">")
    ///     self.set_base_prompt()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Sets basePrompt, used as the delimiter for stripping trailing
    /// prompt text from command output.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator=">") — both terminators are the same
    /// character, meaning APC AOS has only one exec-level prompt
    /// shape rather than a >/# distinction, similar to Teldat's
    /// single-asterisk scheme.
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
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
    public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "APC AOS does not support saveConfig()"
        )
    }
}
