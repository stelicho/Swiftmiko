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
// Sources/Swiftmiko/Optilink/OpEolt9702.swift

import Foundation

/// Common implementation for Optilink EOLT 9702-8P2AB and EOLT
/// 9702-4P devices.
///
/// Maps to netmiko's OptilinkEOLT9702Base(CiscoBaseConnection).
open class OptilinkEOLT9702Base: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Unusual sequence: enters BOTH enable mode and config mode
    /// during session prep, sends a single verbosity-related command
    /// ("vty output show-all" — likely disabling output truncation
    /// on virtual terminal sessions), then immediately unwinds back
    /// out of both modes before session prep completes. The device is
    /// left at the base prompt, ready for normal use, having only
    /// used the elevated privilege briefly to apply one setting.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        _ = try await enterConfigMode()
        _ = try await sendCommand("vty output show-all")
        _ = try await exitConfigMode()
        _ = try await exitEnableMode()
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

    // MARK: Enable Mode

    /// Exit enable mode.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    ///
    /// Fully custom, same "read the echoed command, then separately
    /// wait for the specific base prompt string" two-step shape as
    /// Genexis SOLT33's equivalent method — waits specifically for
    /// the literal "OP_OLT>" prompt rather than a generic pattern.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        _ = try await readUntilPattern(pattern: exitCommand)
        output += try await readUntilPattern(pattern: "OP_OLT>")

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }
}

// MARK: - OptilinkEOLT9702Telnet

/// Optilink EOLT 9702-8P2AB / EOLT 9702-4P Telnet driver — no
/// differences from the base.
///
/// Maps to netmiko's OptilinkEOLT9702Telnet(OptilinkEOLT9702Base).
///
/// Note: only a Telnet variant is defined in the Python source, same
/// as Genexis SOLT33 — no SSH class exists in the original. Preserved
/// exactly rather than assuming an omission.
public final class OptilinkEOLT9702Telnet: OptilinkEOLT9702Base {}
