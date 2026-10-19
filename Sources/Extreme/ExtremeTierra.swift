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
// Sources/Swiftmiko/Extreme/ExtremeTierra.swift

import Foundation

/// Extreme TierraOS SSH driver.
///
/// Maps to netmiko's ExtremeTierraSSH(NoEnable, CiscoSSHConnection).
///
/// Same settle-delay login handler as NOS/SLX, but with its own
/// paging command and save command/confirmation defaults.
public final class ExtremeTierraSSH: CiscoSSHConnection, NoEnable {

    // NoEnable: real Netmiko's mixin is a trivial pass-through
    // (check_enable_mode->True, enable/exit_enable_mode->"") — see
    // Sources/NoEnable.swift for why this needs a direct override
    // rather than a protocol extension default.
    override public func isInEnableMode(checkString: String = "") async throws -> Bool {
        NoEnableBehavior.isInEnableMode()
    }

    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "",
        pattern: String = "",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        NoEnableBehavior.enter()
    }

    @discardableResult
    override public func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        NoEnableBehavior.exit()
    }

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging(command: "terminal length 0")
    }

    override public func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let resolvedDelay = selectDelayFactor(delay)
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(1.0 * resolvedDelay * 1_000_000_000))
    }

    /// Maps to netmiko's save_config(cmd="copy run
    /// flash://config-file/startup-config", confirm=false).
    /// Note confirm defaults to FALSE here, unlike NOS/SLX's true —
    /// a genuine difference, not a copy-paste inconsistency.
    override public func saveConfig(
        command: String = "copy run flash://config-file/startup-config",
        confirm: Bool = false,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
