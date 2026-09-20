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
// Sources/Swiftmiko/Keymile/Keymile.swift

import Foundation

/// Keymile SSH driver (non-NOS product line).
///
/// Maps to netmiko's KeymileSSH(NoEnable, NoConfig, CiscoIOSBase).
///
/// Also inherits from CiscoIOSBase, but with none of NOS's
/// authentication-detection quirk — a more conventional driver.
/// No privilege escalation and no configuration mode via this
/// connection type — hence NoEnable + NoConfig.
public final class KeymileSSH: CiscoIOSBase, NoEnable, NoConfig {

    /// Keymile requires "\r\n" as the line ending.
    /// Maps to netmiko's __init__ override:
    ///     kwargs.setdefault("default_enter", "\r\n")
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r\n"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r">")
    ///     self.set_base_prompt()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Paging

    /// Keymile does not use paging at all — hard no-op.
    /// Maps to netmiko's disable_paging().
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return ""
    }

    // MARK: Output Stripping

    /// Strip a trailing empty line before the standard prompt strip
    /// runs.
    ///
    /// Maps to netmiko's strip_prompt() override.
    ///
    /// Python's `a_string[:-1]` here drops the LAST CHARACTER of the
    /// entire string (not the last line) before delegating to the
    /// base stripper — worth being precise about this distinction,
    /// since it's easy to misread as "drop the last line." This
    /// appears to be compensating for a trailing character (likely a
    /// stray newline or similar) that Keymile's output consistently
    /// includes right before where the real prompt line would
    /// otherwise be found.
    override public func stripPrompt(_ output: String) -> String {
        guard !output.isEmpty else { return output }
        let trimmedLastCharacter = String(output.dropLast())
        return super.stripPrompt(trimmedLastCharacter)
    }

    // MARK: Prompt Detection

    /// Set prompt termination to ">".
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator=">") — same single-terminator scheme as
    /// APC AOS, Teldat, and Calix Exa.
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
