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
// Sources/Swiftmiko/NetApp/NetAppCdot.swift

import Foundation

/// NetApp ONTAP cDOT (clustered Data ONTAP) SSH driver.
///
/// Maps to netmiko's NetAppcDotSSH(NoEnable, BaseConnection).
///
/// No privilege escalation via enable mode on this platform — hence
/// NoEnable. What most drivers call "config mode" is actually ONTAP's
/// diagnostic PRIVILEGE LEVEL, switched via "set -privilege
/// diagnostic" rather than a traditional "configure terminal"-style
/// command. Diagnostic mode is marked by a distinct "*>" prompt
/// character combination.
public final class NetAppCdotSSH: BaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    /// Note the paging-disable command is wrapped in return
    /// characters on both sides, same pattern as NetScaler's and NEC
    /// IX's paging commands.
    override public func sessionPreparation() async throws {
        try await setBasePrompt()
        let pagingCommand = profile.returnCharacter + "rows 0" + profile.returnCharacter
        try await disablePaging(command: pagingCommand)
    }

    // MARK: Yes/No Confirmation Helper

    /// Send a command via timing-based send, automatically answering
    /// "y" if the device responds with a "{y|n}"-style confirmation
    /// prompt.
    ///
    /// Maps to netmiko's send_command_with_y().
    ///
    /// Unlike most Y/N-confirmation handling in this vendor set
    /// (which is baked privately into a single specific method like
    /// exitConfigMode), this is exposed as its own general-purpose
    /// public helper — a caller can use it for ANY command that might
    /// trigger ONTAP's characteristic "{y|n}" confirmation format,
    /// not just a fixed set of built-in operations.
    @discardableResult
    public func sendCommandWithY(
        _ command: String,
        readTimeout: TimeInterval = 2.0,
        stripPrompt: Bool = true,
        stripCommand: Bool = true
    ) async throws -> String {
        var output = try await sendCommandTiming(
            command,
            readTimeout: readTimeout,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand
        )
        if output.contains("{y|n}") {
            output += try await sendCommandTiming(
                "y",
                stripPrompt: false,
                stripCommand: false
            )
        }
        return output
    }

    // MARK: Config Mode — Privilege Level

    /// Maps to netmiko's check_config_mode(check_string="*>").
    override public func isInConfigMode(
        checkString: String = "*>",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Switch to diagnostic privilege level.
    ///
    /// Maps to netmiko's config_mode(config_command="set -privilege
    /// diagnostic -confirmations off").
    ///
    /// The "-confirmations off" flag is doing real work here — it
    /// suppresses ONTAP's own interactive confirmation prompt for
    /// this specific command, meaning this driver doesn't need
    /// sendCommandWithY() for the privilege-switch itself (even
    /// though that helper exists and is presumably meant for other
    /// commands that don't have an equivalent silent flag).
    @discardableResult
    override public func enterConfigMode(
        command: String = "set -privilege diagnostic -confirmations off",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Switch back to admin privilege level.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="set
    /// -privilege admin -confirmations off").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "set -privilege admin -confirmations off",
        pattern: String = ""
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }
}
