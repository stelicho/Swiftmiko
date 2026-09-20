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
// Sources/Swiftmiko/Ruckus/RuckusFastiron.swift

import Foundation

/// Ruckus FastIron (ICX) base driver.
///
/// FastIron requires enable mode before disabling paging.
/// The enable flow supports RADIUS-style prompts for User Name or Login
/// in addition to the standard password prompt.
///
/// Maps to netmiko's RuckusFastironBase(CiscoSSHConnection).
open class RuckusFastironBase: CiscoSSHConnection {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "skip-page-display")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Enter enable mode.
    ///
    /// Supports RADIUS authentication which can prompt for User Name or Login
    /// in addition to the standard password prompt.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "(?:ssword|User Name|Login|No password has been assigned)",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        if checkState, try await isInEnableMode() {
            return ""
        }

        var output = ""
        for _ in 1..<4 {
            try await writeChannel(command + profile.returnCharacter)
            var newData = try await readUntilPromptOrPattern(
                pattern: pattern,
                caseInsensitive: caseInsensitive
            )
            output += newData

            if newData.contains("User Name") || newData.contains("Login") {
                try await writeChannel(profile.username + profile.returnCharacter)
                newData = try await readUntilPromptOrPattern(
                    pattern: pattern,
                    caseInsensitive: caseInsensitive
                )
                output += newData
            }

            if newData.lowercased().contains("ssword") {
                try await writeChannel(secret + profile.returnCharacter)
                newData = try await readUntilPrompt()
                output += newData
                if newData.range(of: "error.*incorrect.*password", options: [.regularExpression, .caseInsensitive]) == nil {
                    break
                }
            }

            if newData.contains("No password has been assigned") {
                break
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        if try await !isInEnableMode() {
            throw SwiftmikoError.commandFailed(
                "Failed to enter enable mode. Please ensure you pass the 'secret' argument to ConnectHandler."
            )
        }
        return output
    }

    // MARK: Save Config

    override public func saveConfig(
        command: String = "write mem",
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

/// Ruckus FastIron SSH driver.
///
/// Maps to netmiko's RuckusFastironSSH(RuckusFastironBase).
public final class RuckusFastironSSH: RuckusFastironBase {}

/// Ruckus FastIron Telnet driver.
///
/// Maps to netmiko's RuckusFastironTelnet(RuckusFastironBase).
public final class RuckusFastironTelnet: RuckusFastironBase {}
