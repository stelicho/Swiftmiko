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
// Sources/Swiftmiko/Ubiquiti/EdgerouterSSH.swift

import Foundation

/// Ubiquiti EdgeRouter SSH driver (EdgeOS).
///
/// EdgeRouter shares VyOS's commit-based configuration model — it
/// inherits directly from VyOSSSH with a few overrides.
///
/// Maps to netmiko's UbiquitiEdgeRouterSSH(VyOSSSH).
public final class UbiquitiEdgeRouterSSH: VyOSSSH {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await setTerminalWidth(command: "set terminal width 512", pattern: "terminal")
        try await disablePaging(command: "set terminal length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Save Config

    override public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        guard !confirm else {
            throw SwiftmikoError.commandFailed("EdgeRouter does not support save_config confirmation.")
        }
        var output = try await enterConfigMode()
        output += try await sendCommand(command, stripPrompt: false, stripCommand: false)
        output += try await exitConfigMode()
        guard output.contains("Done") else {
            throw SwiftmikoError.commandFailed("Save failed with following errors:\n\n\(output)")
        }
        return output
    }
}
