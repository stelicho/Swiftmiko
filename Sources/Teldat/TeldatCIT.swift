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
// Sources/Swiftmiko/Teldat/TeldatCIT.swift

import Foundation

/// Common implementation for Teldat CIT devices (both SSH and Telnet).
///
/// Maps to netmiko's TeldatCITBase(NoEnable, BaseConnection).
///
/// Teldat CIT has no traditional enable step (NoEnable), and its mode
/// system is a hub-and-spoke model rather than a normal state
/// machine: base mode ("*") is the only mode you can reach any other
/// mode from, and the only mode any other mode can return to. There
/// is no direct config→monitor or monitor→config transition — every
/// switch goes through base mode first via Ctrl+P.
///
///   Base mode      "*"          Reached via Ctrl+P (\x10) from anywhere
///   Monitor mode   "+"          Reached from base via "p 3"
///   Config mode    ">"          Reached from base via "p 4"
///   Running config "$"          Reached from base via "p 5"
open class TeldatCITBase: BaseConnection, NoEnable {

    override public nonisolated var promptPattern: String { #"\*"# }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"\*")
    ///     self.set_base_prompt()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: #"\*"#)
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Paging

    /// Teldat has no paging to disable.
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

    // MARK: Prompt Detection

    /// Teldat's base prompt is "hostname *" — both the primary and
    /// alternate terminator are the same asterisk character, since
    /// there's only ever one exec-level prompt shape.
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="*",
    /// alt_prompt_terminator="*").
    override public func setBasePrompt(
        primaryTerminator: String = "*",
        altTerminator: String = "*",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="logout").
    ///
    /// Always returns to base mode first — logging out from inside
    /// config or monitor mode isn't reliable on this platform.
    /// Some firmware versions ask a confirmation question before
    /// actually closing the session, which this answers "yes" to.
    override public func cleanup(command: String = "logout") async throws {
        _ = try await baseMode()

        sessionLog?.fin = true

        try await writeChannel(command + profile.returnCharacter)
        var output = ""
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            output += try await readChannel()
            if output.contains("Do you wish to end") {
                try await writeChannel("yes" + profile.returnCharacter)
                break
            }
        }
    }

    // MARK: Mode Checks

    /// Maps to netmiko's _check_monitor_mode(check_string="+").
    internal func checkMonitorMode(
        checkString: String = "+",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's check_config_mode(check_string=">").
    override public func isInConfigMode(
        checkString: String = ">",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's _check_running_config_mode(check_string="$").
    internal func checkRunningConfigMode(
        checkString: String = "$",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Mode Transitions

    /// Enter monitor mode.
    ///
    /// Maps to netmiko's _monitor_mode(monitor_command="p 3",
    /// pattern=r"\+").
    ///
    /// Always detours through base mode first — Teldat does not allow
    /// switching directly between modes. This can't reuse the base
    /// class's generic config-mode-entry logic because that logic
    /// checks config mode using only its own defaults, which don't
    /// match monitor mode's "+" indicator.
    @discardableResult
    internal func monitorMode(
        command: String = "p 3",
        pattern: String = #"\+"#
    ) async throws -> String {
        _ = try await baseMode()

        var output = ""
        try await writeChannel(normalizeCommand(command))

        if cmdVerifyEnabled {
            output += try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(
                    for: command.trimmingCharacters(in: .whitespaces)
                )
            )
        }
        if output.range(of: pattern, options: .regularExpression) == nil {
            output += try await readUntilPattern(pattern: pattern)
        }
        guard try await checkMonitorMode() else {
            throw SwiftmikoError.commandFailed("Failed to enter monitor mode.")
        }
        return output
    }

    /// Enter configuration mode.
    ///
    /// Maps to netmiko's config_mode(config_command="p 4",
    /// pattern="onfig>").
    @discardableResult
    override public func enterConfigMode(
        command: String = "p 4",
        pattern: String = "onfig>",

        dotAll: Bool = false
    ) async throws -> String {
        _ = try await baseMode()
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Enter running config mode.
    ///
    /// Maps to netmiko's _running_config_mode(config_command="p 5",
    /// pattern=r"onfig\$"). Same hand-rolled pattern as monitorMode()
    /// above, for the same reason — the generic base-class entry path
    /// checks the wrong mode indicator.
    @discardableResult
    internal func runningConfigMode(
        command: String = "p 5",
        pattern: String = #"onfig\$"#
    ) async throws -> String {
        _ = try await baseMode()

        var output = ""
        try await writeChannel(normalizeCommand(command))

        if cmdVerifyEnabled {
            output += try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(
                    for: command.trimmingCharacters(in: .whitespaces)
                )
            )
        }
        if output.range(of: pattern, options: .regularExpression) == nil {
            output += try await readUntilPattern(pattern: pattern)
        }
        guard try await checkRunningConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to enter running config mode.")
        }
        return output
    }

    /// Exit configuration mode.
    ///
    /// Maps to netmiko's exit_config_mode() — there is no dedicated
    /// "exit config" command on this platform. The only way out of
    /// any non-base mode is the same Ctrl+P hub used to enter one.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "",
        pattern: String = ""
    ) async throws -> String {
        return try await baseMode()
    }

    /// Return to base mode from any other mode.
    ///
    /// Maps to netmiko's _base_mode(exit_cmd="\x10", pattern=r"\*").
    ///
    /// \x10 is ASCII DLE (Data Link Escape), sent by a terminal as
    /// Ctrl+P. It is not printable and produces no command echo —
    /// unlike every other write in this driver, there is no
    /// read-the-echo step here, only a direct wait for the base
    /// prompt to reappear.
    @discardableResult
    internal func baseMode(
        exitCommand: String = "\u{10}",
        pattern: String = #"\*"#
    ) async throws -> String {
        try await writeChannel(normalizeCommand(exitCommand))
        let output = try await readUntilPattern(pattern: pattern)
        logger.debug("_base_mode: \(output)")
        return output
    }

    // MARK: Config Set / Save

    /// Send a set of configuration commands.
    ///
    /// Maps to netmiko's send_config_set(), which forwards to the base
    /// implementation with exit_config_mode defaulted to false —
    /// Teldat always enters config mode for a config set and, absent
    /// an explicit exit, is left sitting in it afterward rather than
    /// automatically returning to base.
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
        enterConfigMode: Bool = true,
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

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="save yes").
    ///
    /// Requires the session to already be in BOTH config mode and
    /// running config mode simultaneously — a genuine platform
    /// quirk, not a translation artifact. Both checks must pass
    /// before the save command is sent.
    public func saveConfig(
        command: String = "save yes",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        let inConfig = try await isInConfigMode()
        let inRunningConfig = try await checkRunningConfigMode()
        guard inConfig, inRunningConfig else {
            throw SwiftmikoError.commandFailed(
                "Cannot save if not in config or running config mode"
            )
        }
        return try await sendCommand(
            command,
            stripPrompt: false,
            stripCommand: false
        )
    }
}

// MARK: - TeldatCITSSH

/// Teldat CIT SSH driver — no differences from the base.
/// Maps to netmiko's TeldatCITSSH(TeldatCITBase).
public final class TeldatCITSSH: TeldatCITBase {}

// MARK: - TeldatCITTelnet

/// Teldat CIT Telnet driver.
///
/// Maps to netmiko's TeldatCITTelnet(TeldatCITBase). Overrides the
/// prompt terminators used during Telnet login specifically — the
/// escaped asterisk needs to be passed as a regex fragment, unlike
/// the base class's setBasePrompt which takes the same characters as
/// literal terminators.
public final class TeldatCITTelnet: TeldatCITBase {

    /// Maps to netmiko's telnet_login() override, which supplies
    /// Teldat-specific prompt and credential patterns.
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = #"\*"#,
        altTerminator: String = #"\*"#,
        usernamePattern: String = "Username:",
        passwordPattern: String = "Password:",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 60
    ) async throws -> String {
        return try await super.telnetLogin(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            usernamePattern: usernamePattern,
            passwordPattern: passwordPattern,
            delay: delay,
            maxLoops: maxLoops
        )
    }
}
