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
// Sources/Swiftmiko/Nokia/NokiaSrl.swift

import Foundation

/// Nokia SR Linux (SRL) SSH driver.
///
/// Maps to netmiko's NokiaSrlSSH(BaseConnection, NoEnable).
///
/// No privilege escalation via enable mode — hence NoEnable, and per
/// Netmiko's own docstring, check_enable_mode()/enable()/
/// exit_enable_mode() are all explicitly "not applicable" on this
/// platform.
///
/// SR Linux's CLI prompt is genuinely two lines, carrying a small
/// state-machine's worth of information encoded in symbols:
///
///   --{ running }--[ interface ethernet-1/1 subinterface 1 ]--
///   A:ams01#
///
///   --{ * candidate private private-admin }--[ ... ]--
///   A:ams01#
///
///   --{ + candidate private private-admin }--[ ... ]--
///   A:ams01#
///
/// The asterisk indicates uncommitted changes in the candidate
/// datastore; the plus sign indicates the running config differs
/// from the startup config; an exclamation mark indicates another
/// user committed changes concurrently. This driver only supports
/// the default prompt configuration, per Netmiko's own caveat.
public final class NokiaSrlSSH: BaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    /// Disables terminal auto-complete-on-space and switches the CLI
    /// engine to "basic" mode (removing bottom-toolbar UI text not
    /// needed for automation), then detects the base prompt.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        ansiEscapeCodes = true

        let commands = [
            "environment complete-on-space false",
            "environment cli-engine type basic",
        ]
        for command in commands {
            try await disablePaging(command: command, cmdVerify: true, pattern: "#")
        }

        try await setBasePrompt()
    }

    // MARK: Output Stripping

    /// Strip the trailing prompt, then also strip the additional
    /// context line SR Linux always prepends.
    ///
    /// Maps to netmiko's strip_prompt() override.
    override public func stripPrompt(_ output: String) -> String {
        let base = super.stripPrompt(output)
        return stripContextItems(base)
    }

    /// Strip Nokia SRL's context-line prefix from output.
    ///
    /// Maps to netmiko's _strip_context_items(). Nokia prepends a
    /// context line like "--{ running }--[ ]--" or
    /// "--{ candidate private private-admin }--[ ]--" — this removes
    /// it if it appears as the LAST line of output.
    internal func stripContextItems(_ output: String) -> String {
        let pattern = #"--{.*\B"#
        var lines = output.components(separatedBy: responseReturn)
        guard let lastLine = lines.last else { return output }

        if lastLine.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            lines.removeLast()
            return lines.joined(separator: responseReturn)
        }
        return output
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="#",
    /// alt_prompt_terminator="#", pattern=r"#").
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = "#",
        delay: TimeInterval = 1.0,
        pattern: String? = "#"
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
    }

    // MARK: Config Mode

    /// Enter candidate private configuration mode.
    /// Maps to netmiko's config_mode(config_command="enter candidate
    /// private").
    @discardableResult
    override public func enterConfigMode(
        command: String = "enter candidate private",
        pattern: String = "#",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Check for the candidate-mode context marker in the prompt.
    ///
    /// Maps to netmiko's check_config_mode(check_string=r"\n--{( | \*
    /// | \+ | \+\* | \!\+ | \!\* | \+\!\* | \+\! )candidate",
    /// force_regex=true).
    override public func isInConfigMode(
        checkString: String = #"\n--{( | \* | \+ | \+\* | \!\+ | \!\* | \+\!\* | \+\! )candidate"#,
        pattern: String = "#"
    ) async throws -> Bool {
        return try await isInConfigModeRegex(checkString: checkString, pattern: pattern)
    }

    // MARK: Commit

    /// Commit changes using "commit stay" — stays in candidate mode
    /// after committing rather than returning to running mode.
    /// Maps to netmiko's commit().
    @discardableResult
    public func commit() async throws -> String {
        return try await sendCommand(
            "commit stay",
            stripPrompt: false,
            stripCommand: false
        )
    }

    // MARK: Save Config

    /// Save the current running configuration as the startup
    /// configuration.
    /// Maps to netmiko's save_config(cmd="save startup").
    public func saveConfig(
        command: String = "save startup",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(
            command,
            stripPrompt: false,
            stripCommand: false
        )
    }

    // MARK: Exit Config Mode

    /// Exit candidate private mode, discarding any uncommitted
    /// changes first.
    ///
    /// Maps to netmiko's exit_config_mode() — fully custom, no
    /// super() call at all. Detects uncommitted changes by checking
    /// for the asterisk marker in the freshly-read prompt, discards
    /// them if present (with a warning), then explicitly switches to
    /// "running" mode.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "",
        pattern: String = ""
    ) async throws -> String {
        var output = ""
        try await writeChannel(profile.returnCharacter)
        let prompt = try await readUntilPattern(pattern: "#")

        if hasUncommittedChanges(prompt) {
            output += try await discard()
        }
        output += try await runningMode()
        return output
    }

    // MARK: Config Set

    /// Maps to netmiko's send_config_set(), forwarded with
    /// exitConfigMode defaulted to false — Nokia SRL requires the
    /// session to remain in config mode after a command set.
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
        return try await super.sendConfigSet(commands, exitConfigMode: exitConfigMode)
    }

    // MARK: Internal Helpers

    /// Discard uncommitted changes in candidate private mode.
    /// Maps to netmiko's _discard().
    @discardableResult
    private func discard() async throws -> String {
        logger.warning("Uncommitted changes will be discarted!")
        return try await sendCommand(
            "discard stay",
            stripPrompt: false,
            stripCommand: false
        )
    }

    /// Enter running mode.
    /// Maps to netmiko's _running_mode().
    @discardableResult
    private func runningMode() async throws -> String {
        return try await sendCommand(
            "enter running",
            stripPrompt: false,
            stripCommand: false
        )
    }

    /// Determine whether the candidate configuration has
    /// uncommitted changes, based on the asterisk marker in the
    /// context line.
    ///
    /// Maps to netmiko's _has_uncommitted_changes(prompt).
    private func hasUncommittedChanges(_ prompt: String) -> Bool {
        let pattern = #"\n--{( | \* | \+ | \+\* | \!\+ | \!\* | \+\!\* | \+\! )candidate"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: prompt, range: NSRange(prompt.startIndex..., in: prompt)
              ),
              let matchRange = Range(match.range, in: prompt) else {
            return false
        }
        return prompt[matchRange].contains("*")
    }
}
