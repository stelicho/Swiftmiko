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
// Sources/Swiftmiko/Fiberstore/FiberstoreNetworkOs.swift

import Foundation

/// Fiberstore NetworkOS SSH driver.
///
/// Maps to netmiko's FiberstoreNetworkOSSSH(CiscoBaseConnection).
///
/// A third, distinct Fiberstore OS family (alongside FSOS and FSOS
/// V2) — presumably a different underlying platform or acquisition,
/// with its own config-mode prompt shape and no save-config support
/// at all.
public final class FiberstoreNetworkOSSSH: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — same enable-then-
    /// disable-paging ordering as FSOS V2, but no terminal width step
    /// and no explicit buffer-clear settle delay beyond the fixed one.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "terminal length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Fiberstore NetworkOS does not support saveConfig()"
        )
    }

    // MARK: Config Mode

    /// Maps to netmiko's exit_config_mode(exit_config="exit") — note
    /// this drops the `pattern` argument when forwarding to super,
    /// same "accepted but not forwarded" quirk seen on Calix B6's
    /// check_config_mode. Preserved exactly rather than corrected.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig)
    }

    /// Maps to netmiko's check_config_mode(check_string="(config)#").
    override public func isInConfigMode(
        checkString: String = "(config)#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }
}
