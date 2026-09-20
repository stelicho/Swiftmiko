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
// Sources/Swiftmiko/Ubiquiti/EdgeSSH.swift

import Foundation

/// Ubiquiti EdgeSwitch SSH driver.
/// Mostly conforms to Cisco IOS style syntax with minor changes.
/// This is NOT for EdgeRouter devices.
///
/// Maps to netmiko's UbiquitiEdgeSSH(CiscoSSHConnection).
open class UbiquitiEdgeSSH: CiscoSSHConnection {

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await setBasePrompt()
        try await setTerminalWidth(command: "terminal width 511", pattern: "terminal")
        try await disablePaging()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = #"#.*"#
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    override public func saveConfig(
        command: String = "write memory",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")
        if confirm {
            let confirmMsg = "Are you sure"
            let pattern = "(\(confirmMsg)|#)"
            var output = try await sendCommand(
                command,
                expectString: pattern,
                stripPrompt: false,
                stripCommand: false
            )
            if !confirmResponse.isEmpty && output.contains(confirmMsg) {
                output += try await sendCommand(
                    confirmResponse,
                    expectString: "#",
                    stripPrompt: false,
                    stripCommand: false
                )
            }
            return output
        } else {
            return try await sendCommand(command, stripPrompt: false, stripCommand: false)
        }
    }
}
