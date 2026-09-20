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
// Sources/Swiftmiko/Garderos/GarderosGrs.swift

import Foundation

/// Garderos GRS SSH driver.
///
/// Maps to netmiko's GarderosGrsSSH(CiscoSSHConnection).
///
/// The most input-defensive driver in this vendor set: sendCommand()
/// actively rejects command strings containing embedded newlines or
/// carriage returns before ever writing them to the channel, since
/// Garderos GRS doesn't support multi-line commands at all. Its
/// sendConfigSet() is also a full custom reimplementation rather than
/// a thin parameter forward — each individual command is verified
/// against an EXACT expected response string ("Set.") rather than
/// generic prompt/echo detection, meaning a config command that
/// doesn't produce precisely that response is treated as a hard
/// failure immediately, not just left for the caller to notice later.
public final class GarderosGrsSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read()
    ///     self.set_base_prompt(pri_prompt_terminator="#", alt_prompt_terminator="$")
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        _ = try await testChannelRead()
        try await setBasePrompt(primaryTerminator: "#", altTerminator: "$")
        try await clearBuffer()
    }

    // MARK: Command Execution

    /// Send a command, rejecting any command string containing an
    /// embedded newline or carriage return, and trimming the result.
    ///
    /// Maps to netmiko's send_command() override.
    ///
    /// Garderos GRS does not support multi-line commands at all — a
    /// command string containing "\n" or "\r" would either be
    /// silently misinterpreted or split unpredictably by the device,
    /// so this validates and throws BEFORE ever writing to the
    /// channel, rather than letting a malformed send fail
    /// mysteriously downstream.
    @discardableResult
    override public func sendCommand(
        _ command: String,
        readTimeout: TimeInterval? = nil,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true,
        autoFindPrompt: Bool = true
    ) async throws -> String {
        guard !command.contains("\n"), !command.contains("\r") else {
            throw SwiftmikoError.invalidArgument(
                "The command contains an illegal newline/carriage-return: \(command)"
            )
        }

        let result = try await super.sendCommand(
            command,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern="#").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="configuration
    /// terminal").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configuration terminal",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern="#").
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

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(commit="commit").
    ///
    /// Refuses to run at all if the device is currently in
    /// configuration mode — commit is an operation performed FROM
    /// the exec-level prompt on this platform, not from inside config
    /// mode. Checks the response against two specific phrases: "No
    /// configuration to commit" (nothing staged — a caller error, not
    /// a device failure) and the absence of "Values will be reloaded"
    /// (the actual success marker) — anything else is treated as an
    /// unexpected failure and surfaced verbatim.
    ///
    /// The trailing one-second sleep is a documented, deliberate
    /// settle delay: Garderos genuinely needs a moment to apply the
    /// committed config before a subsequent "show configuration
    /// running" would return valid data — running that command too
    /// soon produces a hard device-side error ("No running
    /// configuration found"), not just stale output.
    @discardableResult
    public func commit(command: String = "commit") async throws -> String {
        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed(
                "Device is in configuration mode. Please exit first."
            )
        }

        let commitResult = try await sendCommand(command)

        guard !commitResult.contains("No configuration to commit") else {
            throw SwiftmikoError.commandFailed(
                "No configuration to commit. Please configure device first."
            )
        }
        guard commitResult.contains("Values will be reloaded") else {
            throw SwiftmikoError.commandFailed(
                "Commit was unsuccessful. Device said: \(commitResult)"
            )
        }

        // Garderos needs a second to apply the config — running
        // "show configuration running" too quickly after committing
        // produces "No running configuration found."
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return commitResult
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="write
    /// startup-configuration", confirm=false).
    ///
    /// Refuses to run while in configuration mode, same as commit().
    /// Also refuses `confirm: true` outright — Garderos always saves
    /// without any confirmation step, so passing confirm=true is a
    /// caller misunderstanding, not a supported variant, and this
    /// throws immediately to make that clear rather than silently
    /// ignoring the flag.
    override public func saveConfig(
        command: String = "write startup-configuration",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed(
                "Device is in configuration mode. Please exit first."
            )
        }
        guard !confirm else {
            throw SwiftmikoError.invalidArgument(
                "Garderos saves the config without the need of confirmation. " +
                "Please set variable 'confirm' to false!"
            )
        }

        let saveResult = try await sendCommand(command)

        guard saveResult.contains("Values are persistently saved to STARTUP-CONF") else {
            throw SwiftmikoError.commandFailed(
                "Saving configuration was unsuccessful. Device said: \(saveResult)"
            )
        }
        return saveResult
    }

    // MARK: Linux Mode

    /// Check if the device is currently in its embedded Linux shell.
    ///
    /// Maps to netmiko's _check_linux_mode(check_string="]#",
    /// pattern="#").
    ///
    /// Internal, not private — not called from anywhere else in this
    /// file (unlike most shell-mode pairs in this vendor set, which
    /// session_preparation or a file transfer class actually invokes),
    /// suggesting this is a manual-use utility for callers who need
    /// to drop into Linux directly, similar in spirit to Asterfusion's
    /// enterVtysh().
    internal func checkLinuxMode(
        checkString: String = "]#",
        pattern: String = "#"
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)
        let output = try await readUntilPrompt(readEntireLine: true)
        return output.contains(checkString)
    }

    /// Enter the embedded Linux shell.
    /// Maps to netmiko's _linux_mode(linux_command="linux-shell",
    /// pattern="#").
    @discardableResult
    internal func linuxMode(
        command: String = "linux-shell",
        pattern: String = "#"
    ) async throws -> String {
        var output = ""
        guard try await !checkLinuxMode() else { return output }

        try await writeChannel(normalizeCommand(command))
        output = try await readUntilPattern(pattern: pattern)

        guard try await checkLinuxMode() else {
            throw SwiftmikoError.commandFailed("Failed to enter Linux mode.")
        }
        return output
    }

    /// Exit the embedded Linux shell.
    /// Maps to netmiko's _exit_linux_mode(exit_linux="exit",
    /// pattern="#").
    @discardableResult
    internal func exitLinuxMode(
        command: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        var output = ""
        guard try await checkLinuxMode() else { return output }

        try await writeChannel(normalizeCommand(command))
        output = try await readUntilPattern(pattern: pattern)

        guard try await !checkLinuxMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit Linux mode")
        }
        return output
    }

    // MARK: Config Command Verification

    /// Execute a single command while already in configuration mode,
    /// verifying it succeeded by checking for an EXACT expected
    /// response.
    ///
    /// Maps to netmiko's _send_config_command().
    ///
    /// This is genuinely different from every other config-command
    /// helper in this vendor set: rather than checking for the
    /// ABSENCE of an error marker (the pattern used almost everywhere
    /// else — CDOT CROS, Eltex ESR, Ericsson IPOS, Juniper, FlexVNF),
    /// this checks for the PRESENCE of one specific, exact success
    /// string: "Set." Anything else — including a genuinely successful-
    /// looking but differently-worded response — is treated as a
    /// failure. This is a stricter contract than most platforms offer,
    /// and it's why Garderos's own sendConfigSet() below can't reuse
    /// the generic base implementation at all.
    ///
    /// Deliberately does NOT check whether the device is in config
    /// mode, and does NOT enter config mode itself — that's the
    /// caller's responsibility, stated explicitly in Netmiko's own
    /// docstring.
    private func sendConfigCommand(
        _ command: String,
        expectString: String? = nil,
        readTimeout: TimeInterval = 10.0
    ) async throws -> String {
        let result = try await sendCommand(
            command,
            readTimeout: readTimeout,
            expectString: expectString
        )

        guard result == "Set." else {
            throw SwiftmikoError.commandFailed(
                "Error executing configuration command \"\(command)\". " +
                "Device said: \(result)"
            )
        }
        return result
    }

    // MARK: Config Set

    /// Send a set of configuration commands, verifying each one
    /// individually against Garderos's strict "Set." response
    /// contract.
    ///
    /// Maps to netmiko's send_config_set() — a full custom
    /// reimplementation rather than a thin forward to the base
    /// class, since the base's generic bypass-pattern-based
    /// verification doesn't match Garderos's exact-response
    /// requirement at all.
    ///
    /// Note this doesn't accept the full parameter surface the base
    /// class's sendConfigSet does (no bypassCommands, errorPattern,
    /// etc.) — those concepts don't apply here, since verification is
    /// always the same fixed exact-match check regardless of which
    /// command is being sent.
    @discardableResult
    public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
        configModeCommand: String? = nil,
        enterConfigMode: Bool = true
    ) async throws -> String {
        var configResults = ""

        guard !commands.isEmpty else { return configResults }

        if enterConfigMode {
            if let configModeCommand {
                configResults += try await self.enterConfigMode(command: configModeCommand)
            } else {
                configResults += try await self.enterConfigMode()
            }
        }

        for command in commands {
            // Verification happens inside sendConfigCommand() itself
            // — it throws on any failure, so a bad command aborts the
            // whole set immediately rather than silently continuing.
            configResults += try await sendConfigCommand(command)
        }

        if exitConfigMode {
            configResults += try await self.exitConfigMode()
        }
        return configResults
    }
}
