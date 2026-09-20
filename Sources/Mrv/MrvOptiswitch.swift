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
// Sources/Swiftmiko/Mrv/MrvOptiswitch.swift

import Foundation

/// MRV Communications OptiSwitch driver.
///
/// Maps to netmiko's MrvOptiswitchSSH(CiscoSSHConnection).
///
/// A distinct MRV product line from LX above — uses the standard
/// "#" prompt terminator rather than LX's doubled ">>", but shares
/// the same parent company's naming and general driver shape.
public final class MrvOptiswitchSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Note setBasePrompt() is called TWICE, with a settle delay
    /// between the two calls — the second call re-detects the prompt
    /// after the buffer-clear delay, rather than before it, unlike
    /// most drivers which detect the prompt once up front. Preserved
    /// exactly as ordered in the source.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "no cli-paging")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await setBasePrompt()
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Enter enable mode — no password required on this platform.
    ///
    /// Maps to netmiko's enable(cmd="enable", pattern=r"#",
    /// re_flags=re.IGNORECASE).
    ///
    /// Netmiko's own comment: "Enable mode on MRV uses no password."
    /// This is a genuinely simpler custom implementation than most
    /// enable() overrides — it sends the command, waits for the
    /// prompt/pattern (never a password prompt, since there isn't
    /// one), and verifies success. No secret is ever written to the
    /// channel at all.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "#",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        var output = ""
        if checkState, try await isInEnableMode() {
            return output
        }

        try await writeChannel(normalizeCommand(command))
        output += try await readUntilPromptOrPattern(
            pattern: pattern,
            readEntireLine: true,
            caseInsensitive: caseInsensitive
        )

        guard try await isInEnableMode() else {
            throw SwiftmikoError.authenticationFailed(
                "Failed to enter enable mode. Please ensure you pass " +
                "the 'secret' argument to ConnectHandler."
            )
        }
        return output
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save config flash") — same
    /// command as MrvLxSSH's equivalent, shared naming convention
    /// across both product lines.
    override public func saveConfig(
        command: String = "save config flash",
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
