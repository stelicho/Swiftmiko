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
// Sources/Swiftmiko/A10/A10.swift

import Foundation

/// A10 Networks SSH driver.
///
/// Maps to netmiko's A10SSH(CiscoSSHConnection).
///
/// A10 requires enable mode before paging can be disabled — the
/// session_preparation order here (enable, THEN disable_paging) is a
/// hard platform requirement, not a stylistic choice, per Netmiko's
/// own comment.
public final class A10SSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.disable_paging(command="terminal length 0")
    ///
    /// Note setTerminalWidth() is deliberately NOT called — Netmiko
    /// leaves this commented out in the source with a note that the
    /// generic terminal-width command does nothing without an
    /// A10-specific equivalent that hasn't been implemented. Carried
    /// over as an omission, not an oversight.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "terminal length 0")
    }

    // MARK: Config Mode

    /// Checks if the device is in configuration mode.
    ///
    /// Maps to netmiko's check_config_mode(check_string=")#").
    ///
    /// This does NOT call super — it's a fully custom implementation.
    /// Two things make that necessary:
    ///
    ///   1. A10's prompt can change unpredictably on router name
    ///      changes, so Netmiko explicitly prefers a fixed-delay read
    ///      (read_channel_timing) over a regex-pattern wait when no
    ///      pattern is supplied — a pattern-based wait risks hanging
    ///      if the prompt shape shifts mid-session.
    ///
    ///   2. Unlicensed A10 devices (e.g. in a GNS3 lab) append a
    ///      literal "(NOLICENSE)" tag to the prompt in both config
    ///      and exec mode:
    ///          LBR1_PROD-EXT_(NOLICENSE)#
    ///          LBR1_PROD-EXT_(config)(NOLICENSE)#
    ///      Left in place, that tag would corrupt a naive check_string
    ///      match — it must be stripped before comparing.
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = ""
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)

        var output: String
        if pattern.isEmpty {
            // Prefer a fixed-delay read over a pattern wait — router
            // name changes can alter the prompt shape unpredictably,
            // and a regex wait would risk hanging on an unexpected
            // prompt string.
            output = try await readChannelTiming(readTimeout: 10.0)
        } else {
            output = try await readUntilPattern(pattern: pattern)
        }

        // Strip the unlicensed-device tag before comparing, whether
        // it appears in config or exec mode.
        output = output.replacingOccurrences(of: "(NOLICENSE)", with: "")

        return output.contains(checkString)
    }

    /// Force-regex variant of the config-mode check.
    ///
    /// Netmiko's single method branches on a `force_regex` boolean
    /// parameter. Swiftmiko splits that branch into two named methods
    /// instead of a boolean flag, since the two code paths return
    /// meaningfully different semantics (substring containment vs.
    /// regex match) and a boolean parameter at the call site
    /// ("isInConfigMode(forceRegex: true)") reads less clearly than a
    /// distinctly named method.
    override public func isInConfigModeRegex(
        checkString: String,
        pattern: String = ""
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)

        var output: String
        if pattern.isEmpty {
            output = try await readChannelTiming(readTimeout: 10.0)
        } else {
            output = try await readUntilPattern(pattern: pattern)
        }

        output = output.replacingOccurrences(of: "(NOLICENSE)", with: "")

        return output.range(of: checkString, options: .regularExpression) != nil
    }

    /// Maps to netmiko's config_mode(config_command="configure terminal",
    /// pattern=r"\(config\)").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure terminal",
        pattern: String = #"\(config\)"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory").
    override public func saveConfig(
        command: String = "write memory",
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
