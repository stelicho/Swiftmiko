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
// Sources/Swiftmiko/SilverPeak/SilverPeakVXOA.swift

import Foundation

/// Silver Peak VXOA SSH driver.
///
/// Maps to netmiko's SilverPeakVXOASSH(CiscoSSHConnection).
///
/// Two profile defaults are forced at construction time:
///   - Line ending defaults to a bare "\r" rather than the more
///     common "\n" — Silver Peak's SSH implementation is picky about
///     this.
///   - globalCmdVerify defaults to false — meaning sendCommand() and
///     friends should NOT wait to see the command echoed back before
///     reading the response. Silver Peak's shell does not reliably
///     echo commands the way most Cisco-family devices do, so waiting
///     for an echo that may never arrive would cause spurious
///     timeouts on every single command.
public final class SilverPeakVXOASSH: CiscoSSHConnection {

    /// Maps to netmiko's __init__ override:
    ///     if kwargs.get("default_enter") is None:
    ///         kwargs["default_enter"] = "\r"
    ///     if kwargs.get("global_cmd_verify") is None:
    ///         kwargs["global_cmd_verify"] = False
    ///
    /// Both defaults are applied only when the caller's profile is
    /// still at its own defaults — an explicit choice by the caller
    /// (e.g. a profile built with returnCharacter already set to
    /// "\n" deliberately) is respected rather than silently
    /// overridden. This mirrors the intent of Python's kwargs.get(...)
    /// is None check, adapted to a value-type profile with no notion
    /// of "unset" beyond comparing against the type's own default.
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
        setGlobalCmdVerify(false)
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.disable_paging(command="no cli session paging enable")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "no cli session paging enable")
    }

    // MARK: Config Mode

    /// Checks if the device is in configuration mode.
    ///
    /// Maps to netmiko's check_config_mode(check_string="(config) #").
    ///
    /// Silver Peak's config prompt has the shape
    /// "(<controller name>) (config) #" — note the literal space
    /// before the closing "#", which is why the check string is
    /// "(config) #" rather than the more common "(config)#" seen on
    /// most Cisco-family devices.
    override public func isInConfigMode(
        checkString: String = "(config) #",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern=r"#.*").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#.*"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }
}
