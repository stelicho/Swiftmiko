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
// Sources/Swiftmiko/Accedian/AccedianSSH.swift

import Foundation

/// Accedian SSH driver.
///
/// Maps to netmiko's AccedianSSH(NoEnable, NoConfig, CiscoSSHConnection).
///
/// No privilege escalation and no configuration mode on this
/// platform — hence NoEnable + NoConfig. The prompt terminator is a
/// colon rather than the more common ">" or "#", and prompt detection
/// uses a longer default delay than most drivers (2.0s vs. the usual
/// 1.0s), suggesting this platform is slower to settle after a
/// carriage return.
public final class AccedianSSH: CiscoSSHConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[:#]")
    ///     self.set_base_prompt()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[:#]")
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Sets basePrompt, used as the delimiter for stripping trailing
    /// prompt text from command output.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=":",
    /// alt_prompt_terminator="#", delay_factor=2.0).
    override public func setBasePrompt(
        primaryTerminator: String = ":",
        altTerminator: String = "#",
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
            "Accedian does not support saveConfig()"
        )
    }
}
