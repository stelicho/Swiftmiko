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
//
//  CiscoS300.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//

// CiscoS300.swift
open class CiscoS300Base: CiscoSSHConnection {

    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await setTerminalWidth(command: "terminal width 511")
        try await disablePaging(command: "terminal datadump")
    }

    override public func saveConfig(
        command: String = "write memory",
        confirm: Bool = true,
        confirmResponse: String = "Y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

// Empty leaf classes — same as Python `pass`
public final class CiscoS300SSH: CiscoS300Base {}
public final class CiscoS300Telnet: CiscoS300Base {}
