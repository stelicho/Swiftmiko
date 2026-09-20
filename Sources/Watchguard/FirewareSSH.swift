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
// Sources/Swiftmiko/Watchguard/FirewareSSH.swift

import Foundation

/// Watchguard Firebox firewall SSH driver.
///
/// Maps to netmiko's WatchguardFirewareSSH(BaseConnection).
public final class WatchguardFirewareSSH: BaseConnection {

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "#",
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
        pattern: String = "#"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    /// Watchguard does not support save_config.
    public func saveConfig() async throws -> String {
        return ""
    }
}
