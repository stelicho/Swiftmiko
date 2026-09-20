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
// Sources/Swiftmiko/Mellanox/MellanoxMlnxos.swift

import Foundation

/// Mellanox MLNX-OS SSH driver.
///
/// Maps to netmiko's MellanoxMlnxosSSH(CiscoSSHConnection).
public final class MellanoxMlnxosSSH: CiscoSSHConnection {

    // MARK: Enable Mode

    /// Enter enable mode.
    ///
    /// Maps to netmiko's enable(cmd="enable", pattern="#",
    /// re_flags=re.IGNORECASE).
    ///
    /// A simpler custom implementation than most enable() overrides
    /// in this vendor set — there's no separate password-prompt
    /// detection step at all here; it just sends the command and
    /// waits for the prompt/pattern to reappear, then verifies enable
    /// mode was actually reached. Presumably MLNX-OS's "enable"
    /// requires no interactive password on the accounts this driver
    /// targets.
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
            throw SwiftmikoError.authenticationFailed("Failed to enter enable mode.")
        }
        return output
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="config term",
    /// pattern=r"\#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config term",
        pattern: String = #"#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's check_config_mode(check_string="(config",
    /// pattern=r"#"). Same deliberately unbalanced parenthesis as
    /// Eltex ESR's check string — matches any config sub-mode
    /// regardless of its specific closing bracket shape.
    override public func isInConfigMode(
        checkString: String = "(config",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Paging

    /// Maps to netmiko's disable_paging(command="no cli session
    /// paging enable"). Same command as Silver Peak's equivalent
    /// setting.
    @discardableResult
    override public func disablePaging(
        command: String = "no cli session paging enable",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.disablePaging(
            command: command,
            pattern: pattern
        )
    }

    /// Exit configuration mode, retrying until the check confirms
    /// success or a bounded attempt count is exhausted.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern="#").
    ///
    /// Netmiko's own comment explains why this loops at all: "Mellanox
    /// does not support a single command to completely exit
    /// configuration mode. Consequently, need to keep checking and
    /// sending 'exit'." Bounded at 13 attempts (`check_count >= 0`
    /// with `check_count` starting at 12, inclusive) — if config mode
    /// is somehow still active after that many "exit"s, this throws
    /// rather than looping indefinitely.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        var output = ""
        var checkCount = 12

        while checkCount >= 0 {
            guard try await isInConfigMode() else { break }
            try await writeChannel(normalizeCommand(exitConfig))
            output += try await readUntilPattern(pattern: pattern)
            checkCount -= 1
        }

        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }

        logger.debug("exit_config_mode: \(output)")
        return output
    }

    // MARK: Save Config

    /// Save the running configuration, explicitly entering and
    /// leaving config mode around the save command.
    ///
    /// Maps to netmiko's save_config(cmd="configuration write").
    ///
    /// Unlike most saveConfig overrides, this doesn't call through
    /// the base saveConfig machinery at all — it manually chains
    /// enable → config mode → the save command → exit config mode,
    /// concatenating all four steps' output together into one
    /// combined result string.
    override public func saveConfig(
        command: String = "configuration write",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        var output = try await enterEnableMode(secret: profile.secret ?? "")
        output += try await enterConfigMode()
        output += try await sendCommand(command)
        output += try await exitConfigMode()
        return output
    }
}
