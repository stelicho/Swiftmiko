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
// Sources/Swiftmiko/Dlink/DlinkDs.swift

import Foundation

/// Common implementation for D-Link DGS/DES switch series (both SSH
/// and Telnet).
///
/// Maps to netmiko's DlinkDSBase(NoEnable, NoConfig,
/// CiscoSSHConnection).
///
/// No privilege escalation and no configuration mode — hence
/// NoEnable + NoConfig. Note some DGS/DES models in this family are
/// web-management-only and don't expose a CLI at all — this driver
/// only applies to the ones that do.
open class DlinkDSBase: CiscoSSHConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"#")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="disable clipaging")
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await disablePaging(command: "disable clipaging")
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save").
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Cleanup

    /// Re-enable paging before disconnecting.
    ///
    /// Maps to netmiko's cleanup(command="logout").
    ///
    /// A small courtesy this driver adds on top of the standard
    /// disconnect sequence: since session preparation explicitly
    /// disabled paging for automation's benefit, cleanup restores it
    /// before logging out — so a human who connects interactively
    /// afterward isn't left with paging silently off and unexpectedly
    /// long, unbroken output.
    override public func cleanup(command: String = "logout") async throws {
        _ = try await sendCommandTiming("enable clipaging")
        try await super.cleanup(command: command)
    }
}

// MARK: - DlinkDSSSH

/// D-Link DGS/DES SSH driver — no differences from the base.
/// Maps to netmiko's DlinkDSSSH(DlinkDSBase).
public final class DlinkDSSSH: DlinkDSBase {}

// MARK: - DlinkDSTelnet

/// D-Link DGS/DES Telnet driver.
/// Maps to netmiko's DlinkDSTelnet(DlinkDSBase). Overrides the
/// default line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class DlinkDSTelnet: DlinkDSBase {

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
}
