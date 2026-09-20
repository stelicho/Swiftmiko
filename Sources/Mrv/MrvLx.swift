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
// Sources/Swiftmiko/Mrv/MrvLx.swift

import Foundation

/// MRV Communications LX driver.
///
/// Maps to netmiko's MrvLxSSH(CiscoSSHConnection).
///
/// The defining quirk of this platform, per Netmiko's own comment:
/// "MRV has a >> for enable mode and config mode instead of # like
/// Cisco." Both enable-mode and config-mode detection are built
/// around a doubled ">>" character rather than the more typical "#".
public final class MrvLxSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Note the pattern "[>|>>]" here is a character class containing
    /// three characters (>, |, >) — the "|" is very likely an
    /// unintended inclusion (perhaps the author meant an alternation
    /// r">|>>" outside a character class, but wrote it inside one by
    /// mistake), since inside a character class "|" has no special
    /// alternation meaning at all; it's just matched as a literal
    /// pipe character. Preserved exactly as written rather than
    /// silently corrected to what was likely intended, since I can't
    /// verify against a real device which behavior is actually
    /// needed.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>|>>]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "no pause")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string=">>").
    override public func isInEnableMode(
        checkString: String = ">>"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Maps to netmiko's enable(cmd="enable", pattern="assword",
    /// re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "assword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        return try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive
        )
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=r"Conf.*>>",
    /// force_regex=true).
    override public func isInConfigMode(
        checkString: String = "Conf.*>>",
        pattern: String = ""
    ) async throws -> Bool {
        return try await isInConfigModeRegex(checkString: checkString, pattern: pattern)
    }

    /// Maps to netmiko's config_mode(config_command="configuration").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configuration",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save config flash").
    override public func saveConfig(
        command: String = "save config flash",
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
