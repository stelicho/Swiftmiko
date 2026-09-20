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
// Sources/Swiftmiko/Nokia/NokiaIsam.swift

import Foundation

/// Nokia ISAM (Intelligent Services Access Manager) SSH driver.
///
/// Maps to netmiko's NokiaIsamSSH(BaseConnection, NoEnable).
///
/// No privilege escalation on this platform — hence NoEnable.
public final class NokiaIsamSSH: BaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Disables paging via a two-command sequence: entering batch
    /// mode, then immediately exiting it — an unusual way to
    /// suppress interactive pagination, achieved as a side effect of
    /// a mode transition rather than a dedicated "no pager" command.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()

        let commands = ["environment mode batch", "exit"]
        for command in commands {
            try await disablePaging(command: command, cmdVerify: true, pattern: "#")
        }

        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Prompt Detection

    /// Detect the base prompt, stripping any ">..." navigation
    /// context and leading "*" (unsaved-changes marker).
    ///
    /// Maps to netmiko's set_base_prompt() override.
    ///
    /// ISAM's prompt can carry navigation context after a ">"
    /// character as you move between config levels — this captures
    /// just the leading hostname-ish portion, discarding both the
    /// leading asterisk and everything from ">" onward.
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )

        let capturePattern = #"\*?(.*?)(>.*)*#"#
        if let regex = try? NSRegularExpression(pattern: capturePattern) {
            let nsPrompt = basePrompt as NSString
            if let match = regex.firstMatch(
                in: basePrompt,
                range: NSRange(location: 0, length: nsPrompt.length)
            ), match.numberOfRanges > 1 {
                basePrompt = nsPrompt.substring(with: match.range(at: 1))
            }
        }
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="logout"). Same best-effort
    /// exit-config-mode-then-always-send-final-command shape as
    /// Juniper, Check Point Gaia, Ericsson MiniLink, and F5 TMSH.
    override public func cleanup(command: String = "logout") async throws {
        do {
            if try await isInConfigMode() {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=">configure",
    /// pattern="#").
    override public func isInConfigMode(
        checkString: String = ">configure",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="configure").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit all") —
    /// note this drops the `pattern` argument when forwarding to
    /// super, same recurring "accepted but not forwarded" quirk seen
    /// several times before (Calix B6, Fiberstore NetworkOS, FlexVNF,
    /// Huawei).
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit all",
        pattern: String = ""
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig)
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="admin save").
    public func saveConfig(
        command: String = "admin save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(
            command,
            stripPrompt: false,
            stripCommand: false
        )
    }
}
