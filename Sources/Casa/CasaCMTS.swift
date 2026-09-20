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
// Sources/Swiftmiko/Casa/CasaCMTS.swift

import Foundation

/// Casa CMTS SSH driver.
///
/// Maps to netmiko's CasaCMTSBase(NoEnable, CiscoSSHConnection).
///
/// No privilege escalation on this platform — hence NoEnable. The
/// most notable behavior here is exitConfigMode(), which must send a
/// raw Ctrl-Z (ASCII 26) to reliably pop out of ANY configuration
/// tier depth in one shot, and has to temporarily suspend command-echo
/// verification around that specific send since a non-printable
/// control character never echoes back the way a normal command
/// string would.
public final class CasaCMTSSSH: CiscoSSHConnection, NoEnable {

    // MARK: Paging

    /// Maps to netmiko's disable_paging(command="page-off").
    @discardableResult
    override public func disablePaging(
        command: String = "page-off",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.disablePaging(
            command: command,
            delay: delay,
            cmdVerify: cmdVerify,
            pattern: pattern
        )
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="config").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    /// Exit configuration mode using Ctrl-Z, reliably popping out of
    /// any nesting depth in the configuration hierarchy in one shot.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config=chr(26),
    /// pattern=r"#.*").
    ///
    /// Because Ctrl-Z (ASCII 26) is non-printable, the device never
    /// echoes it back the way it would echo a normal typed command.
    /// If globalCmdVerify were left on, the base implementation's
    /// attempt to read that echo back would hang waiting for
    /// something that will never arrive. This temporarily forces
    /// globalCmdVerify off for the duration of the call, then
    /// restores whatever the caller's original setting was —
    /// deliberately not just "off," since a caller may have
    /// explicitly configured cmd verification behavior elsewhere in
    /// the session and shouldn't have that silently overwritten
    /// afterward.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "\u{1A}",
        pattern: String = "#.*"
    ) async throws -> String {
        let usingControlZ = exitConfig == "\u{1A}"
        let originalCmdVerify = globalCmdVerify

        if originalCmdVerify != false && usingControlZ {
            setGlobalCmdVerify(false)
        }

        let output = try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )

        if originalCmdVerify != false && usingControlZ {
            setGlobalCmdVerify(originalCmdVerify)
        }

        return output
    }
}
