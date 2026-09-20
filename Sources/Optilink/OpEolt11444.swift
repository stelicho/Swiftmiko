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
// Sources/Swiftmiko/Optilink/OpEolt11444.swift

import Foundation

/// Common implementation for Optilink EOLT 11444 and EOLT 11448
/// devices.
///
/// Maps to netmiko's OptilinkEOLT11444Base(CiscoBaseConnection).
open class OptilinkEOLT11444Base: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Simpler than EOLT 9702's equivalent: enters enable mode,
    /// disables paging while enabled, clears the buffer, then exits
    /// enable mode again — no config-mode excursion at all here.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging()
        try await clearBuffer()
        _ = try await exitEnableMode()
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="configure").
    /// Note "configure" here, not "config" — a genuinely different
    /// command from EOLT 9702's variant, despite the similar product
    /// family name.
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }
}

// MARK: - OptilinkEOLT11444Telnet

/// Optilink EOLT 11444 / EOLT 11448 Telnet driver — no differences
/// from the base.
/// Maps to netmiko's OptilinkEOLT11444Telnet(OptilinkEOLT11444Base).
public final class OptilinkEOLT11444Telnet: OptilinkEOLT11444Base {}
