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
// Sources/Swiftmiko/Dell/DellIsilon.swift

import Foundation

/// Dell Isilon (a Linux-based NAS/storage cluster platform) SSH
/// driver.
///
/// Maps to netmiko's DellIsilonSSH(BaseConnection).
///
/// The most unusual driver in this batch: rather than an enable-mode
/// concept, Isilon aliases EVERY config-mode method directly to its
/// enable-mode equivalent, because "elevating privilege" here really
/// means "become root via sudo su" — there's no separate config
/// context to enter beyond that. It also forces the shell into zsh
/// specifically and manually sets a custom PROMPT variable, since the
/// default shell prompt apparently isn't reliable enough to parse.
public final class DellIsilonSSH: BaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"[#\$]")
    ///     self._zsh_mode()
    ///     self.find_prompt()
    ///     self.set_base_prompt()
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: #"[#\$]"#)
        try await zshMode()
        _ = try await findPrompt()
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="$",
    /// alt_prompt_terminator="#").
    override public func setBasePrompt(
        primaryTerminator: String = "$",
        altTerminator: String = "#",
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

    // MARK: ANSI Handling

    /// Strip NUL bytes from output before the standard ANSI stripper
    /// runs.
    ///
    /// Maps to netmiko's strip_ansi_escape_codes() override — Isilon
    /// apparently emits literal null bytes (\x00) in some output
    /// streams that aren't part of any real ANSI sequence and would
    /// otherwise pollute stripped output.
    override public func stripAnsiEscapeCodes(_ input: String) -> String {
        let cleaned = input.replacingOccurrences(of: "\u{00}", with: "")
        return super.stripAnsiEscapeCodes(cleaned)
    }

    // MARK: Zsh Mode

    /// Force the session into zsh and set a custom, predictable
    /// prompt.
    ///
    /// Maps to netmiko's _zsh_mode(prompt_terminator="$").
    ///
    /// Isilon's default interactive shell prompt is unreliable enough
    /// to parse that this driver switches to zsh explicitly and then
    /// sets PROMPT to a fixed, minimal format — "%m$" (hostname
    /// followed by the terminator) — giving every subsequent prompt
    /// detection something predictable to match against regardless
    /// of what shell configuration the account normally has.
    private func zshMode(promptTerminator: String = "$") async throws {
        let delay = max(selectDelayFactor(0), 1.0)
        let command = profile.returnCharacter + "zsh" + profile.returnCharacter
        try await writeChannel(command)
        try await Task.sleep(nanoseconds: UInt64(0.25 * delay * 1_000_000_000))
        try await setPrompt(terminator: promptTerminator)
        try await Task.sleep(nanoseconds: UInt64(0.25 * delay * 1_000_000_000))
        try await clearBuffer()
    }

    /// Set zsh's PROMPT variable to a fixed, minimal format.
    /// Maps to netmiko's _set_prompt(prompt_terminator="$").
    private func setPrompt(terminator: String = "$") async throws {
        let prompt = "PROMPT='%m\(terminator)'"
        let command = profile.returnCharacter + prompt + profile.returnCharacter
        try await writeChannel(command)
    }

    // MARK: Paging

    /// Isilon has no paging by default — hard no-op.
    /// Maps to netmiko's disable_paging().
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return ""
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Become root via "sudo su", then re-fix the prompt.
    ///
    /// Maps to netmiko's enable(cmd="sudo su", pattern="ssword",
    /// re_flags=re.IGNORECASE).
    ///
    /// This is a hand-rolled enable sequence rather than a call
    /// through the base implementation's parameterized flow — it
    /// specifically waits for a password prompt using timing-based
    /// reads rather than pattern-based ones, then re-applies
    /// setPrompt() with "#" once root is confirmed, since becoming
    /// root changes the effective prompt terminator zsh would
    /// otherwise show.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "sudo su",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        let delay = selectDelayFactor(1.0)
        var output = ""

        if checkState, try await isInEnableMode() {
            return output
        }

        output += try await sendCommandTiming(
            command,
            stripPrompt: false,
            stripCommand: false
        )
        if output.range(
            of: pattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil {
            try await writeChannel(normalizeCommand(secret))
        }
        output += try await readUntilPattern(pattern: "#.*$")
        try await Task.sleep(nanoseconds: UInt64(1.0 * delay * 1_000_000_000))
        try await setPrompt(terminator: "#")

        guard try await isInEnableMode() else {
            throw SwiftmikoError.authenticationFailed("Failed to enter enable mode")
        }
        return output
    }

    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // MARK: Config Mode — Aliased to Enable Mode

    /// Maps to netmiko's check_config_mode() — "use equivalent enable
    /// method." There is no distinct config-mode concept on this
    /// platform; being "in config mode" and being root are the same
    /// state.
    override public func isInConfigMode(
        checkString: String = "#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await isInEnableMode(checkString: checkString)
    }

    /// Maps to netmiko's config_mode(config_command="sudo su",
    /// pattern="ssword") — forwards directly to enterEnableMode(),
    /// same non-super-calling pattern seen on Yamaha.
    @discardableResult
    override public func enterConfigMode(
        command: String = "sudo su",
        pattern: String = "ssword",
        dotAll: Bool = false
    ) async throws -> String {
        return try await enterEnableMode(
            secret: profile.secret ?? "",
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit") —
    /// forwards directly to exitEnableMode().
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return try await exitEnableMode(exitCommand: exitConfig)
    }
}
