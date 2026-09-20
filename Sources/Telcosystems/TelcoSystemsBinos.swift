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
// Sources/Swiftmiko/TelcoSystems/TelcoSystemsBinos.swift

import Foundation

/// Common implementation for TelcoSystems BiNOS devices (both SSH and
/// Telnet).
///
/// Maps to netmiko's TelcoSystemsBinosBase(CiscoBaseConnection).
///
/// Nothing unusual here — standard Cisco-style session prep, a
/// distinct config-mode prompt shape, and no supported save command.
open class TelcoSystemsBinosBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read()
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.disable_paging()
    ///
    /// Note the order: enable() runs before disable_paging(), unlike
    /// most Cisco-family drivers which disable paging first. Some
    /// BiNOS firmware only accepts the paging command at the
    /// privileged level.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging()
    }

    // MARK: Config Mode

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

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "TelcoSystems BiNOS does not support saveConfig()"
        )
    }
}

// MARK: - TelcoSystemsBinosSSH

/// TelcoSystems BiNOS SSH driver — no differences from the base.
/// Maps to netmiko's TelcoSystemsBinosSSH(TelcoSystemsBinosBase).
public final class TelcoSystemsBinosSSH: TelcoSystemsBinosBase {}

// MARK: - TelcoSystemsBinosTelnet

/// TelcoSystems BiNOS Telnet driver — no differences from the base.
/// Maps to netmiko's TelcoSystemsBinosTelnet(TelcoSystemsBinosBase).
public final class TelcoSystemsBinosTelnet: TelcoSystemsBinosBase {}
