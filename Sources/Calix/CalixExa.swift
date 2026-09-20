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
// Sources/Swiftmiko/Calix/CalixExa.swift

import Foundation

/// Common implementation for Calix Exa devices (both SSH and Telnet).
///
/// Maps to netmiko's CalixExaBase(BaseConnection, NoEnable, NoConfig).
///
/// No privilege escalation and no configuration mode — hence
/// NoEnable + NoConfig. Note Python's declaration order here again
/// puts BaseConnection first (same as ApcAosSSH) — as discussed for
/// that file, this ordering doesn't carry the same MRO implications
/// in Swift's protocol conformance model, so it's preserved here
/// purely for documentation parity rather than because it changes
/// resolved behavior.
open class CalixExaBase: BaseConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r">")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="disable session pager")
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
        try await disablePaging(command: "disable session pager")
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator=">") — same single-terminator scheme
    /// seen on APC AOS and Teldat.
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
}

// MARK: - CalixExaSSH

/// Calix Exa SSH driver — no differences from the base.
/// Maps to netmiko's CalixExaSSH(CalixExaBase).
public final class CalixExaSSH: CalixExaBase {}

// MARK: - CalixExaTelnet

/// Calix Exa Telnet driver — no differences from the base.
/// Maps to netmiko's CalixExaTelnet(CalixExaBase).
public final class CalixExaTelnet: CalixExaBase {}
