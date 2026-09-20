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
// Sources/Swiftmiko/Zyxel/ZyxelSSH.swift

import Foundation

/// Zyxel switch SSH driver.
///
/// Maps to netmiko's ZyxelSSH(NoEnable, NoConfig, CiscoSSHConnection).
///
/// Zyxel devices:
///   - Have no privilege escalation step — NoEnable
///   - Have no distinct "configure terminal" mode, but unlike a device
///     that truly can't accept config commands, Zyxel can still take
///     them at the current prompt. NoConfig makes enter/exit config
///     mode safe no-ops rather than hard failures, so commands can
///     still be pushed through.
///   - Emit ANSI escape codes, including a raw "^J" literal (two
///     characters: caret + J, not an actual control byte) that must
///     be normalized before the standard ANSI stripper runs.
///   - Have no paging to disable.
public final class ZyxelSSH: CiscoSSHConnection, NoEnable, NoConfig {

    // MARK: Paging

    /// No paging on Zyxel — nothing to disable.
    /// Maps to netmiko's disable_paging() returning "".
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return ""
    }

    // MARK: Config

    /// Zyxel has no true configuration mode, but commands can still be
    /// sent without ever entering or exiting one. This forwards to the
    /// base implementation with both entering and exiting config mode
    /// disabled by default — NoConfig's no-op enterConfigMode/
    /// exitConfigMode make that safe rather than throwing.
    ///
    /// This is the one place Zyxel's behavior genuinely diverges from
    /// a typical NoConfig device: most NoConfig devices reject
    /// sendConfigSet outright. Zyxel accepts it, just without ever
    /// touching a config-mode prompt.
    ///
    /// Maps to netmiko's send_config_set(), called with
    /// exit_config_mode=False, enter_config_mode=False.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = false,
        readTimeout: TimeInterval? = nil,
        maxLoops: Int? = nil,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = false,
        errorPattern: String = "",
        terminator: String = "#",
        bypassCommands: String? = nil
    ) async throws -> String {
        return try await super.sendConfigSet(
            commands,
            exitConfigMode: exitConfigMode,
            readTimeout: readTimeout,
            maxLoops: maxLoops,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            configModeCommand: configModeCommand,
            cmdVerify: cmdVerify,
            enterConfigMode: enterConfigMode,
            errorPattern: errorPattern,
            terminator: terminator,
            bypassCommands: bypassCommands
        )
    }

    // MARK: Session Preparation

    /// Run standard Cisco-style session prep, then flag that this
    /// device's output contains ANSI escape codes so downstream
    /// output cleaning knows to strip them.
    ///
    /// Maps to netmiko's:
    ///     super().session_preparation()
    ///     self.ansi_escape_codes = True
    override public func sessionPreparation() async throws {
        try await super.sessionPreparation()
        ansiEscapeCodes = true
    }

    // MARK: ANSI Handling

    /// Zyxel emits a literal "^J" at the start of some output where a
    /// normal device would just send a newline. Replace it with the
    /// configured return character before handing off to the standard
    /// ANSI stripper.
    ///
    /// Maps to netmiko's:
    ///     output = re.sub(r"^\^J", self.RETURN, string_buffer)
    ///     return super().strip_ansi_escape_codes(output)
    override public func stripAnsiEscapeCodes(_ input: String) -> String {
        let caretJPattern = #"^\^J"#
        let replaced = input.replacingOccurrences(
            of: caretJPattern,
            with: profile.returnCharacter,
            options: .regularExpression
        )
        return super.stripAnsiEscapeCodes(replaced)
    }
}
