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
// Sources/Swiftmiko/Vertiv/VertivMphSSH.swift

import Foundation

/// Vertiv MPH Power Distribution Unit base driver.
/// Should work with any Vertiv device with an RPC2 module.
///
/// Maps to netmiko's VertivMPHBase(NoEnable, NoConfig, CiscoSSHConnection).
///
/// No privilege escalation and no configuration mode via this
/// connection type — hence NoEnable + NoConfig.
open class VertivMPHBase: CiscoSSHConnection, NoEnable, NoConfig {

    // NoConfig: real Netmiko's mixin is a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->""),
    // not a throw — see Sources/NoConfig.swift for why this needs a
    // direct override rather than a protocol extension default.
    override public func isInConfigMode(checkString: String = "", pattern: String = "") async throws -> Bool {
        NoConfigBehavior.isInConfigMode()
    }

    @discardableResult
    override public func enterConfigMode(command: String = "", pattern: String = "", dotAll: Bool = false) async throws -> String {
        NoConfigBehavior.enter()
    }

    @discardableResult
    override public func exitConfigMode(exitConfig: String = "exit", pattern: String = "") async throws -> String {
        NoConfigBehavior.exit()
    }

    // NoEnable: same trivial-pass-through story — see Sources/NoEnable.swift.
    override public func isInEnableMode(checkString: String = "") async throws -> Bool {
        NoEnableBehavior.isInEnableMode()
    }

    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "",
        pattern: String = "",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        NoEnableBehavior.enter()
    }

    @discardableResult
    override public func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        NoEnableBehavior.exit()
    }

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "cli->")
        try await setBasePrompt()
    }

    override public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    override public func cleanup(command: String = "logout") async throws {
        try await super.cleanup(command: command)
    }
}

/// Vertiv MPH SSH driver.
/// Maps to netmiko's VertivMPHSSH(VertivMPHBase).
public final class VertivMPHSSH: VertivMPHBase {}
