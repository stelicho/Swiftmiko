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
/// Maps to netmiko's VertivMPHBase(CiscoSSHConnection).
open class VertivMPHBase: CiscoSSHConnection {

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
