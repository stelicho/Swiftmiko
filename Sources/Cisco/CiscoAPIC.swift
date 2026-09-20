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
//  CiscoAPIC.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//

// CiscoAPIC.swift
// Note: inherits LinuxSSHConnection, NOT CiscoBaseConnection.
// Mirrors netmiko's CiscoApicSSH(LinuxSSH) exactly.
public class CiscoAPICSSH: LinuxSSHConnection {

    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
        // APIC has paging enabled by default unlike standard Linux.
        // Call CiscoSSHConnection's disablePaging explicitly —
        // mirrors Python's CiscoSSHConnection.disable_paging(self, ...)
        try await ciscoDisablePaging(command: "terminal length 0")
    }

    // This helper mirrors the explicit super-call Netmiko makes to reach
    // CiscoSSHConnection's disable_paging over LinuxSSH's no-op version.
    private func ciscoDisablePaging(command: String) async throws {
        _ = try await sendCommand(command)
    }
}
