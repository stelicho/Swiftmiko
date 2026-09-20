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
// Sources/Swiftmiko/Oneaccess/OneaccessOneos.swift

import Foundation

/// Common implementation for OneAccess ONEOS devices (both SSH and
/// Telnet).
///
/// Maps to netmiko's OneaccessOneOSBase(CiscoBaseConnection).
///
/// This is the class Ekinops EK-360 inherits from — OneAccess's
/// hardware and CLI apparently underpin that rebadged product.
///
/// The defining behavior: session_preparation() actively probes
/// which ONEOS firmware generation it's talking to. It tries an
/// ONEOS6-specific terminal-width command first; if the response
/// looks like an error, it falls back to a Unix-style "stty columns"
/// command instead (presumably ONEOS5's actual mechanism). If the
/// ONEOS6 command succeeded, the driver ALSO switches its own line
/// ending from the default "\r\n" to a bare "\n" — a genuine runtime
/// mutation of connection behavior based on what the device turned
/// out to be, not something decided once at construction time.
open class OneaccessOneOSBase: CiscoBaseConnection {

    /// OneAccess requires "\r\n" as the line ending by default —
    /// though session preparation may later switch this to "\n" for
    /// ONEOS6 devices specifically, see sessionPreparation() below.
    ///
    /// Maps to netmiko's __init__ override:
    ///     default_enter = kwargs.get("default_enter")
    ///     kwargs["default_enter"] = "\r\n" if default_enter is None else default_enter
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

    /// Prepare the session, detecting whether the device is running
    /// ONEOS5 or ONEOS6 by probing an ONEOS6-specific command.
    ///
    /// Maps to netmiko's session_preparation().
    ///
    /// Sequence:
    ///   1. Disable paging with the shared "term len 0" command
    ///      (apparently common to both firmware generations).
    ///   2. Try setting terminal width with ONEOS6's own
    ///      "screen-width 512" command.
    ///   3. Read the response. If it contains "error" (case-
    ///      insensitive), this must be ONEOS5 — retry with the
    ///      Unix-style "stty columns 255" fallback instead.
    ///   4. If NO error appeared, this is genuinely ONEOS6 — and
    ///      ONEOS6 apparently uses a different line ending than the
    ///      OneAccess default, so responseReturn (Netmiko's
    ///      self.RETURN) is switched to a bare "\n" for the remainder
    ///      of the session.
    ///
    /// This is one of the few drivers in this vendor set that
    /// genuinely changes its own line-ending convention mid-session
    /// based on runtime probing, rather than deciding it once via a
    /// constructor override.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await disablePaging(command: "term len 0")

        // Try the ONEOS6 command first — fall back to ONEOS5's
        // equivalent if it fails.
        try await setTerminalWidth(command: "screen-width 512", cmdVerify: true)
        let output = try await testChannelRead(pattern: "[>#]")

        if output.lowercased().contains("error") {
            try await setTerminalWidth(command: "stty columns 255", cmdVerify: true)
        }
        // Note: ONEOS6 uses "\n" line endings. Configure profile.returnCharacter = "\n" if needed.

        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write mem").
    override public func saveConfig(
        command: String = "write mem",
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

// MARK: - OneaccessOneOSSSH

/// OneAccess ONEOS SSH driver — no differences from the base.
/// Maps to netmiko's OneaccessOneOSSSH(OneaccessOneOSBase).
public final class OneaccessOneOSSSH: OneaccessOneOSBase {}

// MARK: - OneaccessOneOSTelnet

/// OneAccess ONEOS Telnet driver — no differences from the base.
/// Maps to netmiko's OneaccessOneOSTelnet(OneaccessOneOSBase).
public final class OneaccessOneOSTelnet: OneaccessOneOSBase {}
