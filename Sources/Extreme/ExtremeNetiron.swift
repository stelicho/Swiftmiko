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
// Sources/Swiftmiko/Extreme/ExtremeNetiron.swift

import Foundation

/// Common implementation for Extreme (Brocade/Foundry-derived)
/// NetIron devices.
///
/// Maps to netmiko's ExtremeNetironBase(CiscoSSHConnection).
open class ExtremeNetironBase: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "skip-page-display")
        try await setTerminalWidth()
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

/// Extreme NetIron SSH driver — no differences from the base.
/// Maps to netmiko's ExtremeNetironSSH(ExtremeNetironBase).
public final class ExtremeNetironSSH: ExtremeNetironBase {}

/// Extreme NetIron Telnet driver.
/// Maps to netmiko's ExtremeNetironTelnet(ExtremeNetironBase).
/// Overrides the default line ending to "\r\n" unless the caller's
/// profile already specifies one.
public final class ExtremeNetironTelnet: ExtremeNetironBase {

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
