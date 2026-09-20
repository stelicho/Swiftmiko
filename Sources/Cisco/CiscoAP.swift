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
//  CiscoAP.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//
// CiscoAP.swift
public class CiscoAPSSH: CiscoBaseConnection, NoConfig {
    // Protocol provides enterConfigMode, exitConfigMode, sendConfigSet

    override public func sessionPreparation() async throws {
        try await setTerminalWidth(command: "terminal width 132")
        try await disablePaging()
        try await setBasePrompt()
    }
}

