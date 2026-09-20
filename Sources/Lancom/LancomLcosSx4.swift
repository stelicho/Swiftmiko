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
// Sources/Swiftmiko/Lancom/LancomLcosSx4.swift

import Foundation

/// LANCOM LCOS SX 4.x SSH driver.
///
/// Maps to netmiko's LancomLCOSSX4SSH(CiscoSSHConnection).
///
/// LANCOM does not allow running "Exec" (normal, non-configuration)
/// commands while in configuration mode. Rather than exiting config
/// mode first, this platform offers a "do" prefix escape hatch — the
/// same convention Cisco IOS-XR-family devices use — letting an exec
/// command run without leaving config mode at all. Both save_config()
/// and cleanup() check for this condition and prepend "do " when
/// needed.
///
/// Note: Netmiko's own source has a typo in its class-level attribute
/// name — `promt_pattern` instead of `prompt_pattern` — which is
/// never actually referenced anywhere else in the file, meaning it's
/// dead, unused code. Not carried forward here; if you find a newer
/// Netmiko release that fixes and actually uses this attribute, worth
/// revisiting.
public final class LancomLCOSSX4SSH: CiscoSSHConnection {

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="(config)#",
    /// pattern="#").
    override public func isInConfigMode(
        checkString: String = "(config)#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session, using the "do" escape hatch
    /// if currently in config mode.
    ///
    /// Maps to netmiko's cleanup(command="logout").
    override public func cleanup(command: String = "logout") async throws {
        var resolvedCommand = command
        if try await isInConfigMode() {
            resolvedCommand = "do " + command
        }
        try await super.cleanup(command: resolvedCommand)
    }

    // MARK: Save Config

    /// Save the running configuration, using the "do" escape hatch
    /// if currently in config mode.
    ///
    /// Maps to netmiko's save_config(cmd="copy running-config
    /// startup-config").
    ///
    /// Sends the command directly rather than through the base
    /// saveConfig machinery, since the "do" prefix logic doesn't fit
    /// cleanly into the generic confirm/confirmResponse flow.
    override public func saveConfig(
        command: String = "copy running-config startup-config",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        var resolvedCommand = command
        if try await isInConfigMode() {
            resolvedCommand = "do " + command
        }
        return try await sendCommand(resolvedCommand)
    }
}
