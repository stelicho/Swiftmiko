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
// Sources/Swiftmiko/Apresia/ApresiaAeos.swift

import Foundation

/// Common implementation for Apresia AEOS devices (both SSH and
/// Telnet).
///
/// Maps to netmiko's ApresiaAeosBase(CiscoSSHConnection).
///
/// The most distinctive part of this driver is disablePaging(),
/// which doesn't blindly send a paging-disable command — it first
/// checks the running config to see whether paging is already
/// disabled, and only sends the change if it isn't AND the caller has
/// explicitly opted into allowing automatic config changes via
/// allowAutoChange. Without that flag set, this driver will happily
/// leave paging enabled rather than mutate the device's
/// configuration without permission.
open class ApresiaAeosBase: CiscoSSHConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging()
    }

    // MARK: Paging

    /// Conditionally disable paging, checking the running config
    /// first.
    ///
    /// Maps to netmiko's disable_paging(command="terminal length 0").
    ///
    /// Sequence:
    ///   1. Enter enable mode — required to read running-config.
    ///   2. Run "show running-config | include terminal length 0"
    ///      (or whatever command string was supplied) to check
    ///      whether paging is already disabled.
    ///   3. Only if allowAutoChange is true AND the command is NOT
    ///      already present in the running config, actually send the
    ///      disable command via the base class's implementation.
    ///   4. Always exit enable mode afterward, regardless of which
    ///      branch was taken.
    ///
    /// If allowAutoChange is false and paging genuinely isn't
    /// disabled on the device, this method returns an empty string
    /// having made no changes — silently leaving paging enabled
    /// rather than throwing. That's carried over faithfully from
    /// Netmiko even though a caller relying on paging actually being
    /// off afterward should set allowAutoChange explicitly.
    @discardableResult
    override public func disablePaging(
        command: String = "terminal length 0",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")

        let checkCommand = "show running-config | include \(command)"
        let showRun = try await sendCommand(checkCommand)

        var output = ""
        if profile.allowAutoChange && !showRun.contains(command) {
            output += try await super.disablePaging(
                command: command,
                delay: delay,
                cmdVerify: cmdVerify,
                pattern: pattern
            )
        }

        try await exitEnableMode()
        return output
    }
}

// MARK: - ApresiaAeosSSH

/// Apresia AEOS SSH driver — no differences from the base.
/// Maps to netmiko's ApresiaAeosSSH(ApresiaAeosBase).
public final class ApresiaAeosSSH: ApresiaAeosBase {}

// MARK: - ApresiaAeosTelnet

/// Apresia AEOS Telnet driver.
///
/// Maps to netmiko's ApresiaAeosTelnet(ApresiaAeosBase). Overrides
/// the default line ending to "\r\n" unless the caller's profile
/// already specifies one.
public final class ApresiaAeosTelnet: ApresiaAeosBase {

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
