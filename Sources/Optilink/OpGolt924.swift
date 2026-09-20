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
// Sources/Swiftmiko/Optilink/OpGolt924.swift

import Foundation

/// Common implementation for Optilink GOLT 92408A and GOLT
/// 92408A16A devices.
///
/// Maps to netmiko's OptilinkGOLT924Base(CiscoBaseConnection).
///
/// A different Optilink product family (GPON OLT rather than
/// Ethernet OLT) — no paging or config-mode setup at all during
/// session prep, and its own distinct enable-mode exit prompt
/// ("gpon>" rather than EOLT's "OP_OLT>").
open class OptilinkGOLT924Base: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — the simplest of the
    /// three Optilink files, just prompt detection.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
    }

    // MARK: Enable Mode

    /// Exit enable mode.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="exit") — same
    /// structural shape as EOLT 9702's equivalent, but waiting for
    /// the literal "gpon>" prompt instead of "OP_OLT>".
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        _ = try await readUntilPattern(pattern: exitCommand)
        output += try await readUntilPattern(pattern: "gpon>")

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }
}

// MARK: - OptilinkGOLT924Telnet

/// Optilink GOLT 92408A / GOLT 92408A16A / GOLT 92416A Telnet driver
/// — no differences from the base.
///
/// Maps to netmiko's OptilinkGOLT924Telnet(OptilinkGOLT924Base).
///
/// Note the class docstring covers three model names ("GOLT 92416A
/// telnet driver / GOLT 92408A telnet driver") while the module
/// docstring above it only lists two ("GOLT 92408A" / "GOLT
/// 92408A16A") — a small inconsistency in Netmiko's own comments
/// worth being aware of but not something to resolve here, since it
/// doesn't affect actual behavior.
public final class OptilinkGOLT924Telnet: OptilinkGOLT924Base {}
