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
//  CiscoNXOS.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//

// CiscoNXOS.swift
open class CiscoNXOSBase: CiscoSSHConnection {

    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        // NX-OS echoes command before returning prompt — wait for it
        try await testChannelRead(pattern: "[>#]")
        try await setTerminalWidth(command: "terminal width 511",
                                   pattern: "terminal width 511")
        try await disablePaging()
        try await setBasePrompt()
    }

    // NX-OS has a quirky \r pattern that corrupts MD5 on 9K platforms
    override public func normalizeLinefeeds(_ input: String) -> String {
        let pattern = #/(\r\r\n\r|\r\r\n|\r\n)/#
        var result = input.replacing(pattern, with: responseReturn)
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    override public func saveConfig(
        command: String = "copy running-config startup-config",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")
        // NX-OS is slow — use a generous read timeout
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

public final class CiscoNXOSSSH: CiscoNXOSBase {}
public final class CiscoNXOSTelnet: CiscoNXOSBase {}
