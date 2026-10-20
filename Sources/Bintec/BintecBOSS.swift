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
import Foundation

// Support for BinTec/Funkwerk (BOSS) devices
//
// Maps to netmiko's BintecBossBase(NoEnable, NoConfig,
// CiscoBaseConnection) — this platform has neither an enable mode nor
// a traditional conf-t style config mode; its "cmd=X" command style
// is flat, so configuration commands execute directly.
open class BintecBossBase: CiscoBaseConnection, NoEnable, NoConfig {

    // NoEnable: real Netmiko's mixin is a trivial pass-through
    // (check_enable_mode->True, enable/exit_enable_mode->"") — see
    // Sources/NoEnable.swift for why this needs a direct override
    // rather than a protocol extension default.
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

    // NoConfig: real Netmiko's mixin is a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->"") —
    // see Sources/NoConfig.swift for why this needs a direct override
    // rather than a protocol extension default.
    override public func isInConfigMode(checkString: String = "", pattern: String = "") async throws -> Bool {
        NoConfigBehavior.isInConfigMode()
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        NoConfigBehavior.enter()
    }

    @discardableResult
    override public func exitConfigMode(exitConfig: String = "exit", pattern: String = "") async throws -> String {
        NoConfigBehavior.exit()
    }

    // Prepare session and set base prompt
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
    }

    // Save Config to flash.
    @discardableResult
    override public func saveConfig(
        command: String = "cmd=save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // Reloads the device.
    @discardableResult
    public func reloadDevice(
        command: String = "cmd=reboot",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommandTiming(command)
    }
}

public final class BintecBossSSH: BintecBossBase {}

public final class BintecBossTelnet: BintecBossBase {}
