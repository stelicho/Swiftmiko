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

// Brocade Fabric OS — callers should set returnCharacter: "\r" in ConnectionProfile (netmiko's default_enter)
class BrocadeFOSSSH: CiscoSSHConnection {

    override func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
    }
}
