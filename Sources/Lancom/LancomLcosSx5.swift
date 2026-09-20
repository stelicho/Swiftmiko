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
// Sources/Swiftmiko/Lancom/LancomLcosSx5.swift

import Foundation

/// LANCOM LCOS SX 5.x SSH driver.
///
/// Maps to netmiko's LancomLCOSSX5SSH(CiscoSSHConnection).
///
/// Unlike SX4's "do" escape-hatch approach, SX5 handles the same
/// underlying restriction (exec commands can't run in config mode)
/// by simply exiting config mode outright before running save_config
/// or cleanup — a more conventional pattern, matching most other
/// drivers in this vendor set. It's not clear from this file alone
/// whether SX5 dropped the "do" prefix support entirely or just
/// doesn't use it in the same places SX4 does; worth checking real
/// device documentation if that distinction matters for other
/// commands not covered here.
public final class LancomLCOSSX5SSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Prepare the session, landing in Privileged EXEC mode by
    /// default.
    ///
    /// Maps to netmiko's session_preparation().
    ///
    /// Netmiko's own comment explains why enable mode is entered
    /// unconditionally here rather than left to the caller: "EXEC"
    /// mode (the unprivileged default) offers inconsistent command
    /// options on this platform, so Privileged EXEC is treated as the
    /// only reliable baseline to operate from.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await enterEnableMode(secret: profile.secret ?? "", enablePattern: "#")
        try await setBasePrompt()
        try await disablePaging()
        try await clearBuffer()
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="(Config)#",
    /// pattern="#").
    /// Note the capital "C" in "(Config)#" — genuinely different
    /// capitalization from SX4's lowercase "(config)#", not a
    /// transcription error.
    override public func isInConfigMode(
        checkString: String = "(Config)#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Enable Mode

    /// Maps to netmiko's exit_enable_mode(exit_command="end").
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "end"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session, exiting config mode first if
    /// necessary.
    ///
    /// Maps to netmiko's cleanup(command="logout").
    override public func cleanup(command: String = "logout") async throws {
        if try await isInConfigMode() {
            _ = try await exitConfigMode()
        }
        try await super.cleanup(command: command)
    }

    // MARK: Save Config

    /// Save the running configuration to memory, exiting config mode
    /// first if necessary.
    ///
    /// Maps to netmiko's save_config(cmd="write memory confirm",
    /// confirm=false, confirm_response="y").
    override public func saveConfig(
        command: String = "write memory confirm",
        confirm: Bool = false,
        confirmResponse: String = "y"
    ) async throws -> String {
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
