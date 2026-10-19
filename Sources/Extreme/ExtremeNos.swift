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
// Sources/Swiftmiko/Extreme/ExtremeNos.swift

import Foundation

/// Extreme NOS/VDX SSH driver.
///
/// Maps to netmiko's ExtremeNosSSH(NoEnable, CiscoSSHConnection).
///
/// No privilege escalation — hence NoEnable. Structurally near-
/// identical to ExtremeSlxSSH and ExtremeTierraSSH below — all three
/// add a fixed post-login settle delay via specialLoginHandler()
/// rather than reacting to any particular banner text.
public final class ExtremeNosSSH: CiscoSSHConnection, NoEnable {

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

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
    }

    // MARK: Login Handling

    /// Add a fixed delay after login completes.
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    /// Unlike every other specialLoginHandler in this vendor set,
    /// this one reacts to nothing at all — it doesn't inspect any
    /// banner text or wait for any pattern. It's purely a settle
    /// delay: send a bare return, then pause, presumably because this
    /// platform needs a moment before it's ready to accept the next
    /// command reliably.
    override public func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let resolvedDelay = selectDelayFactor(delay)
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(1.0 * resolvedDelay * 1_000_000_000))
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="copy running-config
    /// startup-config", confirm=true, confirm_response="y").
    override public func saveConfig(
        command: String = "copy running-config startup-config",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
