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
// Sources/Swiftmiko/Genexis/GenexisSolt33.swift

import Foundation

/// Common implementation for Genexis SOLT33 devices.
///
/// Maps to netmiko's GenexisSOLT33Base(CiscoBaseConnection).
///
/// Similar to SMCI's SMIS driver: paging and terminal width are both
/// configured from INSIDE config mode rather than at the exec
/// prompt. This one goes further — it also enters enable mode first,
/// then carefully unwinds both config mode and enable mode explicitly
/// at the end of session preparation, leaving the session sitting
/// back at the base ">" prompt once ready for normal use.
open class GenexisSOLT33Base: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.config_mode()
    ///     cmd = "line width 256"
    ///     self.set_terminal_width(command=cmd, pattern=cmd)
    ///     self.disable_paging(command="screen-rows per-page 0")
    ///     self.clear_buffer()
    ///     self.exit_config_mode()
    ///     self.exit_enable_mode()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        _ = try await enterConfigMode()

        let widthCommand = "line width 256"
        try await setTerminalWidth(command: widthCommand, pattern: widthCommand)
        try await disablePaging(command: "screen-rows per-page 0")
        try await clearBuffer()

        _ = try await exitConfigMode()
        _ = try await exitEnableMode()
    }

    // MARK: Enable Mode

    /// Exit enable mode.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    ///
    /// Fully custom rather than a forward to super: reads until the
    /// echoed exit command appears first, THEN waits for the ">"
    /// prompt separately — a two-step read sequence rather than a
    /// single combined wait, presumably needed because this device's
    /// echo and prompt don't arrive together reliably enough for a
    /// single pattern match to catch both.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        _ = try await readUntilPattern(pattern: exitCommand)
        output += try await readUntilPattern(pattern: ">")

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }
}

// MARK: - GenexisSOLT33Telnet

/// Genexis SOLT33 Telnet driver — no differences from the base.
///
/// Maps to netmiko's GenexisSOLT33Telnet(GenexisSOLT33Base).
///
/// Note: Netmiko's own source defines only a Telnet variant for this
/// device — no corresponding SSH class exists in the original file.
/// Preserved exactly as given rather than assuming an SSH driver was
/// simply omitted by mistake; if SOLT33 does support SSH in practice,
/// that would need its own class added once confirmed, following the
/// same `GenexisSOLT33Base` pattern used here.
public final class GenexisSOLT33Telnet: GenexisSOLT33Base {}
