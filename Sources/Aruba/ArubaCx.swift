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
// Sources/Swiftmiko/Aruba/ArubaCx.swift

import Foundation

/// Aruba AOS-CX SSH driver.
///
/// Maps to netmiko's ArubaCxSSH(CiscoSSHConnection).
public final class ArubaCxSSH: CiscoSSHConnection {

    /// Aruba AOS-CX requires a bare "\r" line ending.
    /// Maps to netmiko's __init__ override.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r"
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
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="no page")
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "no page")
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="(config)#").
    override public func isInConfigMode(
        checkString: String = "(config)#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Enter configuration mode.
    ///
    /// Maps to netmiko's config_mode(config_command="configure
    /// term").
    ///
    /// AOS-CX auto-completes commands on a space character, so an
    /// abbreviated "config" would trigger an unwanted auto-complete
    /// mid-command — "configure" must be spelled out in full (though
    /// "term" itself remains abbreviated, apparently safely).
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure term",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }
}
