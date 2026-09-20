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
// Sources/Swiftmiko/Extreme/ExtremeWing.swift

import Foundation

/// Extreme WiNG (wireless controller) SSH driver.
///
/// Maps to netmiko's ExtremeWingSSH(CiscoSSHConnection).
public final class ExtremeWingSSH: CiscoSSHConnection {

    /// Maps to netmiko's session_preparation() — note the alternation
    /// pattern "r\">|#\"" rather than the more common single
    /// character class "[>#]"; functionally equivalent but written
    /// differently in the original, preserved as-is.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">|#")
        try await setBasePrompt()
        try await setTerminalWidth(command: "terminal width 512", pattern: "terminal")
        try await disablePaging(command: "no page")
    }
}
