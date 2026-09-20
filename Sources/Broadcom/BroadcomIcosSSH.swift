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

// Implements support for Broadcom Icos devices.
// Syntax is almost identical to Cisco IOS in most cases
public final class BroadcomIcosSSH: CiscoSSHConnection {

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
    }

    // Checks if the device is in configuration mode or not.
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(checkString: checkString, pattern: pattern)
    }

    // Enter configuration mode.
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(command: command, pattern: pattern)
    }

    // Exit configuration mode.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig)
    }

    // Exit enable mode.
    @discardableResult
    override public func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // Saves configuration.
    @discardableResult
    override public func saveConfig(
        command: String = "write memory",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
