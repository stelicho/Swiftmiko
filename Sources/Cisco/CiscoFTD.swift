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
//  CiscoFTD.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//
// Sources/Swiftmiko/Cisco/CiscoFTD.swift

import Foundation
import Logging

/// Cisco Firepower Threat Defense (FTD) SSH driver.
///
/// Maps to netmiko's CiscoFtdSSH(NoConfig, CiscoSSHConnection).
///
/// FTD has a two-layer CLI architecture:
///
///   Layer 1 — FTD CLI (top level, where SSH lands)
///     Prompt:   firepower>
///     Purpose:  System management, diagnostics, packet capture
///     Limits:   No config mode, no firewall policy changes
///
///   Layer 2 — Diagnostic CLI (ASA/Lina subsystem)
///     Entered:  system support diagnostic-cli → enable
///     Prompt:   firepower#
///     Purpose:  ASA-style troubleshooting commands
///     Exit:     Ctrl+A, D  (detach signal — NOT "exit")
///
/// Because there is no configuration mode at the FTD CLI level,
/// this driver conforms to NoConfig. All sendConfigSet() calls will
/// throw notImplemented — FTD policy is managed through FMC or FDM.
public final class CiscoFtdSSH: CiscoSSHConnection, NoConfig {

    // MARK: - State

    /// Tracks whether we are currently inside the diagnostic CLI subprocess.
    ///
    /// Maps to netmiko's self._in_diagnostic_cli instance variable.
    ///
    /// This is critical for exit_enable_mode() to know whether it needs
    /// to send the detach signal. If we never entered the diagnostic CLI,
    /// there is nothing to detach from.
    ///
    /// Because this is an class property, access is automatically
    /// serialized — no explicit lock needed, unlike Netmiko's approach.
    private var inDiagnosticCLI: Bool = false

    // MARK: - Session Preparation

    /// Prepare the session after SSH authentication succeeds.
    ///
    /// FTD session prep is deliberately minimal — we just wait for the
    /// initial prompt and detect the base prompt string.
    ///
    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///
    /// Notice what is NOT here: no disable_paging(), no terminal width.
    /// The FTD CLI does not support those commands at the top level.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
    }

    // MARK: - Enable Mode (Diagnostic CLI Entry)

    /// Check whether we are currently in the diagnostic CLI (enable mode).
    ///
    /// Maps to netmiko's:
    ///     def check_enable_mode(self, check_string="#"):
    ///         return super().check_enable_mode(check_string=check_string)
    ///
    /// On FTD, "enable mode" means we are inside the diagnostic CLI
    /// at privileged exec level — indicated by "#" in the prompt.
    override public func isInEnableMode(checkString: String = "#") async throws -> Bool {
        return try await super.isInEnableMode(checkString: "#")
    }

    /// Enter enable mode on FTD by dropping into the diagnostic CLI.
    ///
    /// Maps to netmiko's enable() — the most complex method in this driver.
    ///
    /// Two-phase process:
    ///   Phase 1: Send "system support diagnostic-cli" to enter the
    ///            ASA/Lina subprocess. This puts us at the diagnostic
    ///            CLI user exec prompt (">").
    ///
    ///   Phase 2: If we landed at ">" (user exec), send "enable" with
    ///            an empty password to reach privileged exec ("#").
    ///            The diagnostic CLI enable password is always empty.
    ///
    /// Note: `secret` parameter is accepted for protocol conformance
    /// but ignored — FTD diagnostic CLI always uses an empty password.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "system support diagnostic-cli",
        pattern: String = "ssword",
        enablePattern: String? = #"#"#,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        // Already in enable mode — nothing to do
        guard try await !isInEnableMode() else { return "" }

        // Phase 1: Enter the diagnostic CLI subprocess
        let diagCmd = "system support diagnostic-cli"
        try await writeChannel(normalizeCommand(diagCmd))

        // Read command echo if verification is on
        if cmdVerifyEnabled {
            _ = try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(
                    for: diagCmd.trimmingCharacters(in: .whitespaces)
                )
            )
        }

        // Wait for the diagnostic CLI to initialize and present a prompt
        var output = try await readUntilPattern(pattern: "[>#]")

        // Mark that we are now inside the subprocess
        // This flag is what exitEnableMode() checks later
        inDiagnosticCLI = true
        logger.debug("Entered diagnostic CLI subprocess")

        // Phase 2: If we're at user exec (">"), elevate to enable ("#")
        // Check the last non-empty line of output for the prompt character
        let lastLine = output
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .last ?? ""

        if lastLine.range(of: #">\s*$"#, options: .regularExpression) != nil {
            logger.debug("At user exec prompt — sending enable")

            // Call the base CiscoSSHConnection enable() with:
            //   cmd="enable"          (normal enable command)
            //   pattern="ssword"      (wait for password prompt)
            //   enable_pattern=r"\#"  (final elevated prompt)
            //   check_state=False     (we already know we're not enabled)
            //
            // The password sent will be empty — FTD diagnostic CLI
            // always accepts an empty enable password.
            output += try await super.enterEnableMode(
                secret: "",            // Always empty on FTD
                command: "enable",
                pattern: "ssword",
                enablePattern: #"#"#,
                checkState: false
            )
        }

        try await setBasePrompt()
        logger.debug("FTD diagnostic CLI ready, prompt: '\(basePrompt)'")
        return output
    }

    /// Exit the diagnostic CLI and return to the top-level FTD CLI.
    ///
    /// Maps to netmiko's exit_enable_mode() — the most unusual method
    /// in any Netmiko driver.
    ///
    /// Does NOT send "exit". Instead sends Ctrl+A, D (\x01 + "d").
    /// This is the terminal detach signal for the diagnostic CLI process.
    /// Sending "exit" would only exit enable mode within the diagnostic
    /// CLI, leaving you still inside the subprocess at ">".
    /// The detach signal jumps straight back to the FTD CLI from any
    /// privilege level within the diagnostic CLI.
    ///
    /// Maps to netmiko's:
    ///     output += self._send_command_str("\x01d", expect_string=r">",
    ///                                     cmd_verify=False)
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"  // Accepted but not used — see note above
    ) async throws -> String {
        var output = ""

        guard inDiagnosticCLI else {
            logger.debug("Not in diagnostic CLI — nothing to exit")
            return output
        }

        // \x01 = Ctrl+A, "d" = detach
        // This is a raw terminal control sequence, not a CLI command.
        // cmd_verify must be False — there is no echo to wait for.
        let detachSequence = "\u{01}d"  // \x01d in Python
        output += try await sendCommandTiming(
            detachSequence,
            expectString: ">",
            cmdVerify: false
        )

        inDiagnosticCLI = false
        try await setBasePrompt()
        logger.debug("Detached from diagnostic CLI, back at FTD CLI")
        return output
    }

    // MARK: - Config Mode (always false on FTD)

    /// FTD has no configuration mode at the CLI level.
    ///
    /// Maps to netmiko's:
    ///     def check_config_mode(self, check_string="", ...): return False
    ///
    /// NoConfig protocol provides sendConfigSet() → throws notImplemented.
    /// This override ensures isInConfigMode() always returns false so
    /// any callers that check before acting get a clean answer.
    override public func isInConfigMode(
        checkString: String = "",
        pattern: String = ""
    ) async throws -> Bool {
        return false
    }
}
