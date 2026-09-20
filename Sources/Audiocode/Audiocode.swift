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
// Sources/Swiftmiko/Audiocode/Audiocode.swift

import Foundation

// MARK: - AudiocodeBase

/// Common implementation shared by all AudioCode drivers.
///
/// Maps to netmiko's AudiocodeBase(BaseConnection).
///
/// AudioCode's prompt can carry a trailing "*" to indicate unsaved
/// changes (e.g. "MYDEVICE*#"), which several methods here have to
/// account for explicitly when comparing or stripping prompt text.
open class AudiocodeBase: BaseConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    /// AudioCode requires a bare "\r" line ending.
    /// Maps to netmiko's __init__ override.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt()
    ///     self.disable_paging()
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
        try await disablePaging()
        try await clearBuffer()
    }

    // MARK: Prompt Detection

    /// Sets basePrompt, accounting for AudioCode's unsaved-changes
    /// asterisk marker.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="#",
    /// alt_prompt_terminator=">").
    ///
    /// The detected prompt is checked by its LAST character against
    /// the terminators (unlike Adva's last-three-character check) —
    /// AudioCode's terminators are single characters. If the prompt
    /// carries the unsaved-changes marker ("MYDEVICE*#" or
    /// "MYDEVICE*>"), the trailing two characters are stripped rather
    /// than just one, so the "*" doesn't end up embedded in
    /// basePrompt and break later prompt-stripping comparisons.
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        let resolvedPattern = pattern ?? #"\*?"# + promptPattern

        let prompt = try await findPrompt(delay: delay, pattern: resolvedPattern)

        guard let lastChar = prompt.last,
              String(lastChar) == primaryTerminator || String(lastChar) == altTerminator else {
            throw SwiftmikoError.unexpectedPrompt(
                "Router prompt not found: \(prompt.debugDescription)"
            )
        }

        if prompt.count == 1 {
            basePrompt = prompt
        } else if prompt.hasSuffix("*#") || prompt.hasSuffix("*>") {
            basePrompt = String(prompt.dropLast(2))
        } else {
            basePrompt = String(prompt.dropLast(1))
        }
    }

    /// Find the current prompt, defaulting to a pattern that
    /// optionally matches the unsaved-changes asterisk.
    /// Maps to netmiko's find_prompt().
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        let resolvedPattern = pattern ?? (#"\*?"# + promptPattern)
        return try await super.findPrompt(delay: delay, pattern: resolvedPattern)
    }

    // MARK: Paging

    /// Re-enable window paging.
    ///
    /// Maps to netmiko's _enable_paging() — the base implementation
    /// is a no-op returning "". Firmware-specific subclasses
    /// (Audiocode72Base, AudiocodeBase66) override this with real
    /// config-command sequences; AudiocodeShellBase overrides it back
    /// to a no-op since shell-only firmware has no paging concept at
    /// all.
    @discardableResult
    internal func enablePaging(delay: TimeInterval = 0.5) async throws -> String {
        return ""
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=r"(?:\)#|\)\*#)",
    /// pattern=r"..#", force_regex=True).
    ///
    /// Both the check string and the search pattern are regexes here
    /// — force_regex=True is the default, unlike most drivers in this
    /// vendor set where regex matching is the exception rather than
    /// the rule. The check string alternation accounts for the same
    /// unsaved-changes asterisk seen in setBasePrompt.
    override public func isInConfigMode(
        checkString: String = #"(?:\)#|\)\*#)"#,
        pattern: String = "..#"
    ) async throws -> Bool {
        return try await isInConfigModeRegex(checkString: checkString, pattern: pattern)
    }

    /// Regex-based config-mode check — see the AudioCode base for why
    /// this device defaults to regex matching rather than substring
    /// containment. Mirrors the split introduced for A10.
    override public func isInConfigModeRegex(
        checkString: String,
        pattern: String
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)
        let output = try await readUntilPattern(pattern: pattern)
        return output.range(of: checkString, options: .regularExpression) != nil
    }

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit").
    ///
    /// Best-effort: re-enables paging and exits config mode if
    /// currently in it, swallowing any error along the way — the
    /// final "exit" command is always sent regardless of whether
    /// those cleanup steps succeeded.
    override public func cleanup(command: String = "exit") async throws {
        do {
            _ = try await enablePaging()
            if try await isInConfigMode() {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort cleanup — swallow any failure here, same as
            // Netmiko's bare `except Exception: pass`.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }

    // MARK: Enable Mode

    /// Maps to netmiko's enable(cmd="enable", pattern="ssword",
    /// enable_pattern="#", re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = "#",
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        return try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive,
            defaultUsername: defaultUsername
        )
    }

    /// Maps to netmiko's exit_enable_mode(exit_command="disable").
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "disable"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    /// Exit configuration mode, looping until fully out.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern=r"#").
    ///
    /// AudioCode's configuration contexts can nest — "configure
    /// system" then a sub-menu then a sub-sub-menu — so a single
    /// "exit" may only pop one level. This keeps sending "exit" up to
    /// 10 times, checking config-mode status after each, until either
    /// it succeeds or the depth limit is hit (at which point it
    /// throws rather than silently giving up).
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        var output = ""
        let maxExitDepth = 10

        guard try await isInConfigMode() else { return output }

        for _ in 0..<maxExitDepth {
            try await writeChannel(normalizeCommand(exitConfig))

            if cmdVerifyEnabled {
                output += try await readUntilPattern(
                    pattern: NSRegularExpression.escapedPattern(
                        for: exitConfig.trimmingCharacters(in: .whitespaces)
                    )
                )
            }
            if !pattern.isEmpty {
                output += try await readUntilPattern(pattern: pattern)
            } else {
                output += try await readUntilPrompt(readEntireLine: true)
            }

            if try await !isInConfigMode() {
                return output
            }
        }

        throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
    }

    // MARK: Config Set

    /// Send a set of configuration commands.
    ///
    /// Maps to netmiko's send_config_set() override.
    ///
    /// AudioCode has multiple distinct top-level configuration
    /// contexts ("configure system", "configure voip", "configure
    /// network", etc.) rather than one universal "configure
    /// terminal", so there is no sensible default — a caller who
    /// wants to enter config mode automatically MUST specify
    /// configModeCommand explicitly, or this throws immediately with
    /// a message explaining exactly what's needed and giving
    /// examples.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
        readTimeout: TimeInterval? = nil,
        maxLoops: Int? = 150,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = true,
        errorPattern: String = "",
        terminator: String = #"\*?#"#,
        bypassCommands: String? = nil
    ) async throws -> String {
        if enterConfigMode && configModeCommand == nil {
            throw SwiftmikoError.invalidArgument(
                """
                sendConfigSet() for the Audiocode drivers require that you specify the
                configModeCommand. For example, configModeCommand="configure system"
                (or "configure voip" or "configure network" etc.)
                """
            )
        }
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

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write").
    public func saveConfig(
        command: String = "write",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")

        var output: String
        if confirm {
            output = try await sendCommandTiming(command)
            if !confirmResponse.isEmpty {
                output += try await sendCommandTiming(confirmResponse)
            } else {
                output += try await sendCommandTiming(profile.returnCharacter)
            }
        } else {
            output = try await sendCommand(command)
        }
        return output
    }

    // MARK: Reload

    /// Reload the device.
    ///
    /// Maps to netmiko's _reload_device(cmd_save="reload now",
    /// cmd_no_save="reload without-saving", reload_save=True).
    @discardableResult
    internal func reloadDevice(
        saveCommand: String = "reload now",
        noSaveCommand: String = "reload without-saving",
        reloadSave: Bool = true
    ) async throws -> String {
        let command = reloadSave ? saveCommand : noSaveCommand
        _ = try await enablePaging()
        try await enterEnableMode(secret: profile.secret ?? "")
        return try await sendCommandTiming(command)
    }
}

// MARK: - Audiocode72Base

/// Common implementation for AudioCode devices running the 7.2 CLI.
///
/// Maps to netmiko's Audiocode72Base(AudiocodeBase).
///
/// Both paging control methods here are genuinely different from a
/// typical single-command disable_paging: they enter enable mode,
/// wait, clear the buffer, then push a two-line configuration
/// sequence through sendConfigSet — AudioCode 7.2 has no direct
/// "no pager"-equivalent single command.
open class Audiocode72Base: AudiocodeBase {

    /// Maps to netmiko's disable_paging() — falls back to the
    /// AudioCode 7.2-specific config sequence only when the caller
    /// hasn't supplied an explicit command string.
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        guard command.isEmpty else {
            return try await super.disablePaging(
                command: command,
                pattern: pattern
            )
        }

        let commands = ["cli-settings", "window-height 0"]

        try await enterEnableMode(secret: profile.secret ?? "")
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        try await clearBuffer()

        return try await sendConfigSet(
            commands,
            configModeCommand: "config system"
        )
    }

    /// Re-enable window paging.
    /// Maps to netmiko's _enable_paging().
    @discardableResult
    override internal func enablePaging(
        delay: TimeInterval = 0.5
    ) async throws -> String {
        let commands = ["cli-settings", "window-height automatic"]

        try await enterEnableMode(secret: profile.secret ?? "")
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        try await clearBuffer()

        return try await sendConfigSet(
            commands,
            configModeCommand: "config system"
        )
    }
}

/// AudioCode 7.2 CLI Telnet driver — no differences from the base.
/// Maps to netmiko's Audiocode72Telnet(Audiocode72Base).
public final class Audiocode72Telnet: Audiocode72Base {}

/// AudioCode 7.2 CLI SSH driver — no differences from the base.
/// Maps to netmiko's Audiocode72SSH(Audiocode72Base).
public final class Audiocode72SSH: Audiocode72Base {}

// MARK: - AudiocodeBase66

/// Common implementation for AudioCode devices running 6.6 firmware.
///
/// Maps to netmiko's AudiocodeBase66(AudiocodeBase).
///
/// Structurally identical to Audiocode72Base's paging methods, but
/// with 6.6's own command vocabulary ("cli-terminal" /
/// "set window-height N" rather than "cli-settings" /
/// "window-height N").
open class AudiocodeBase66: AudiocodeBase {

    /// Maps to netmiko's disable_paging().
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        guard command.isEmpty else {
            return try await super.disablePaging(
                command: command,
                pattern: pattern
            )
        }

        let commands = ["cli-terminal", "set window-height 0"]

        try await enterEnableMode(secret: profile.secret ?? "")
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        try await clearBuffer()

        return try await sendConfigSet(
            commands,
            configModeCommand: "config system"
        )
    }

    /// Re-enable window paging.
    /// Maps to netmiko's _enable_paging().
    @discardableResult
    override internal func enablePaging(
        delay: TimeInterval = 0.5
    ) async throws -> String {
        let commands = ["cli-terminal", "set window-height 100"]

        try await enterEnableMode(secret: profile.secret ?? "")
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        try await clearBuffer()

        return try await sendConfigSet(
            commands,
            configModeCommand: "config system"
        )
    }
}

/// AudioCode 6.6 firmware SSH driver — no differences from the base.
/// Maps to netmiko's Audiocode66SSH(AudiocodeBase66).
public final class Audiocode66SSH: AudiocodeBase66 {}

/// AudioCode 6.6 firmware Telnet driver — no differences from the
/// base.
/// Maps to netmiko's Audiocode66Telnet(AudiocodeBase66).
public final class Audiocode66Telnet: AudiocodeBase66 {}

// MARK: - AudiocodeShellBase

/// Common implementation for AudioCode 6.6-era devices that expose
/// ONLY a raw shell interface, not the standard CLI.
///
/// Maps to netmiko's AudiocodeShellBase(NoEnable, AudiocodeBase).
///
/// This is architecturally the most different driver in the whole
/// AudioCode family — the prompt grammar is completely different
/// ("/>" and nested paths like "/CONFiguration>" rather than "[>#]"),
/// there is no enable mode (NoEnable), and paging genuinely does not
/// exist on this firmware variant at all — both disablePaging and
/// enablePaging are hard no-ops here rather than falling back to a
/// config-command sequence.
open class AudiocodeShellBase: AudiocodeBase, NoEnable {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     self.write_channel(self.RETURN)
    ///     self.write_channel(self.RETURN)
    ///     self._test_channel_read(pattern=r"/>")
    ///     self.set_base_prompt()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    ///
    /// Sends TWO bare returns before waiting for the prompt — a
    /// single return apparently isn't reliable enough to wake this
    /// shell up on first connect.
    override public func sessionPreparation() async throws {
        try await writeChannel(profile.returnCharacter)
        try await writeChannel(profile.returnCharacter)
        try await testChannelRead(pattern: "/>")
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=r"/>",
    /// alt_prompt_terminator="", pattern=r"/>").
    ///
    /// Unlike the standard AudiocodeBase implementation, this stores
    /// the ENTIRE detected prompt as basePrompt rather than stripping
    /// any trailing terminator — the shell's nested-path prompts
    /// (e.g. "/CONFiguration>") are meaningful in full and shouldn't
    /// be truncated.
    override public func setBasePrompt(
        primaryTerminator: String = "/>",
        altTerminator: String = "",
        delay: TimeInterval = 1.0,
        pattern: String? = "/>"
    ) async throws {
        let prompt = try await findPrompt(delay: delay, pattern: pattern)
        guard prompt.range(of: primaryTerminator, options: .regularExpression) != nil else {
            throw SwiftmikoError.unexpectedPrompt(
                "Router prompt not found: \(prompt.debugDescription)"
            )
        }
        basePrompt = prompt
    }

    /// Maps to netmiko's find_prompt(pattern=r"/>").
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = "/>"
    ) async throws -> String {
        return try await super.findPrompt(delay: delay, pattern: pattern)
    }

    // MARK: Config Set / Mode

    /// Maps to netmiko's send_config_set() override — same shape as
    /// the base class's, but with shell-appropriate defaults
    /// (terminator=r"/.*>" instead of r"\*?#").
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
        readTimeout: TimeInterval? = nil,
        maxLoops: Int? = 150,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = true,
        errorPattern: String = "",
        terminator: String = "/.*>",
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

    /// Maps to netmiko's config_mode(config_command="",
    /// pattern=r"/.*>").
    /// Note the empty default config_command — navigating this
    /// shell's context tree is done via configModeCommand at the
    /// sendConfigSet call site, not via a fixed "configure" command.
    @discardableResult
    override public func enterConfigMode(
        command: String = "",
        pattern: String = "/.*>",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(command: command, pattern: pattern, dotAll: dotAll)
    }

    /// Maps to netmiko's check_config_mode(check_string=r"/CONFiguration>",
    /// pattern=r"/.*>", force_regex=True).
    override public func isInConfigMode(
        checkString: String = "/CONFiguration>",
        pattern: String = "/.*>"
    ) async throws -> Bool {
        return try await isInConfigModeRegex(checkString: checkString, pattern: pattern)
    }

    /// Maps to netmiko's exit_config_mode(exit_config="..",
    /// pattern=r"/>").
    /// Note the exit command is literally ".." — this shell's
    /// context navigation apparently mirrors filesystem path
    /// traversal syntax, consistent with its slash-delimited prompts.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "..",
        pattern: String = "/>"
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig, pattern: pattern)
    }

    // MARK: Paging — Genuinely Unsupported

    /// Not supported on this firmware — hard no-op, unlike the 7.2
    /// and 6.6 base classes which fall back to a real config
    /// sequence.
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

    /// Not supported on this firmware.
    /// Maps to netmiko's _enable_paging() returning "".
    @discardableResult
    override internal func enablePaging(
        delay: TimeInterval = 0.5
    ) async throws -> String {
        return ""
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="SaveConfiguration").
    override public func saveConfig(
        command: String = "SaveConfiguration",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Reload

    /// Maps to netmiko's _reload_device(cmd_save="SaveAndReset",
    /// cmd_no_save="ReSetDevice").
    @discardableResult
    override internal func reloadDevice(
        saveCommand: String = "SaveAndReset",
        noSaveCommand: String = "ReSetDevice",
        reloadSave: Bool = true
    ) async throws -> String {
        return try await super.reloadDevice(
            saveCommand: saveCommand,
            noSaveCommand: noSaveCommand,
            reloadSave: reloadSave
        )
    }

    // MARK: Output Stripping

    /// Strip a command echo, plus this shell's own SIP/PING status
    /// banner noise, from command output.
    ///
    /// Maps to netmiko's strip_command() override.
    ///
    /// The shell apparently prints an unrelated SIP/PING status line
    /// pattern in some outputs that has nothing to do with the actual
    /// command that was run — that noise is filtered out first,
    /// before the command echo itself is stripped, before finally
    /// deferring to the base implementation for whatever remains.
    override public func stripCommand(
        _ commandString: String,
        output: String
    ) -> String {
        let bannerPattern = #"^SIP.*[\s\S]?PING.*>?.*[\s\S]?.*>?$"#
        var cleaned = output.replacingOccurrences(
            of: bannerPattern,
            with: "",
            options: [.regularExpression]
        )

        let trimmedCommand = commandString.trimmingCharacters(in: .whitespaces)
        let commandPattern = NSRegularExpression.escapedPattern(for: trimmedCommand)
        cleaned = cleaned.replacingOccurrences(
            of: commandPattern,
            with: "",
            options: [.regularExpression]
        )

        return super.stripCommand(commandString, output: cleaned)
    }

    /// Strip the leading "/" (and optional trailing ">") prompt
    /// fragment from output, on every line.
    ///
    /// Maps to netmiko's strip_prompt() override.
    override public func stripPrompt(_ output: String) -> String {
        let pattern = "^/>?"
        let cleaned = output.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression]
        )
        return super.stripPrompt(cleaned)
    }
}

/// AudioCode shell-only SSH driver — no differences from the base.
/// Maps to netmiko's AudiocodeShellSSH(AudiocodeShellBase).
public final class AudiocodeShellSSH: AudiocodeShellBase {}

/// AudioCode shell-only Telnet driver — no differences from the
/// base.
/// Maps to netmiko's AudiocodeShellTelnet(AudiocodeShellBase).
public final class AudiocodeShellTelnet: AudiocodeShellBase {}
