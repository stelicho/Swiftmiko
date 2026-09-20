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
// Sources/Swiftmiko/Netgear/NetgearProsafe.swift

import Foundation

/// Netgear ProSafe OS SSH driver.
///
/// Maps to netmiko's NetgearProSafeSSH(CiscoSSHConnection).
public final class NetgearProSafeSSH: CiscoSSHConnection {

    /// ProSafe requires a bare "\r" line ending.
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

    /// ProSafe OS requires enable mode to disable paging — same
    /// ordering constraint as A10, Aruba OS, and ProCurve.
    ///
    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "terminal length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="(Config)#").
    /// Capital "C", matching LANCOM SX5's convention rather than the
    /// more common lowercase "(config)#" seen elsewhere.
    override public func isInConfigMode(
        checkString: String = "(Config)#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="configure",
    /// pattern=r"\)\#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = #")#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern=r"\#").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = #"#"#
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Save the running configuration, ensuring enable mode and
    /// exiting config mode first if necessary.
    ///
    /// Maps to netmiko's save_config(save_cmd="write memory
    /// confirm").
    ///
    /// Note: Netmiko's own parameter here is named `save_cmd`, not
    /// the more standard `cmd` used by every other save_config
    /// override in this vendor set — likely an inconsistency in the
    /// original rather than an intentional API difference, since it
    /// means this override's signature doesn't quite match its own
    /// parent's `save_config(cmd=...)` positionally if called with
    /// keyword arguments matching the base class convention. Renamed
    /// to `command` here for consistency with every other
    /// saveConfig() override in Swiftmiko, since preserving Python's
    /// naming inconsistency would just propagate confusion rather
    /// than serve any real translation-fidelity purpose.
    ///
    /// Netmiko's own comment, worth keeping: "ProSafe doesn't allow
    /// saving whilst within configuration mode" — hence the explicit
    /// exitConfigMode() check before the save actually runs.
    override public func saveConfig(
        command: String = "write memory confirm",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")

        if try await isInConfigMode() {
            _ = try await exitConfigMode()
        }

        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
