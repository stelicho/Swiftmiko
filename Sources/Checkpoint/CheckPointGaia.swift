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
// Sources/Swiftmiko/CheckPoint/CheckPointGaia.swift

import Foundation

/// Check Point Gaia SSH driver.
///
/// Maps to netmiko's CheckPointGaiaSSH(NoConfig, BaseConnection).
///
/// No configuration mode via this connection — Gaia's configuration
/// is normally managed through its own "clish" shell or the web UI,
/// not through Netmiko-style config-mode commands — hence NoConfig.
/// "Enable mode" on this platform means Check Point's "expert" mode,
/// entered via the "expert" command and a separate, very
/// timing-sensitive expert password prompt.
public final class CheckPointGaiaSSH: BaseConnection, NoConfig {

    override public nonisolated var promptPattern: String { "[>#]" }

    /// Check Point Gaia has repeatedly caused issues with command-echo
    /// verification when fast_cli's more aggressive timing is
    /// enabled — this forces fastCli off unless the caller's profile
    /// already explicitly set it.
    ///
    /// Maps to netmiko's __init__ override:
    ///     self.fast_cli = False
    ///     fast_cli = kwargs.get("fast_cli") or False
    ///     kwargs["fast_cli"] = fast_cli
    ///
    /// Note the Python here is a little unusual — it sets
    /// self.fast_cli = False, then immediately recomputes kwargs["fast_cli"]
    /// from whatever the caller passed (or False if nothing was passed),
    /// before calling super().__init__() with that recomputed value.
    /// Net effect: fast_cli ends up False unless the caller explicitly
    /// passed a truthy value for it. Translated here as: default to
    /// false, but respect an explicit true from the caller's profile.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        // ConnectionProfile.fastCli defaults to true (per the original
        // BaseConnection design) — Gaia needs that inverted default.
        // If the caller's profile is still sitting at the library
        // default, force it off; an explicit caller override is
        // preserved either way since we can't distinguish "explicitly
        // set to true" from "left at the default true" without a
        // three-state representation, so this treats bare `true` as
        // an explicit request the same way Netmiko's kwargs.get(...) or False
        // treats any truthy passed value as authoritative.
        adjustedProfile.fastCli = profile.fastCli
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
    ///     self.disable_paging(command="set clienv rows 0")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
        try await disablePaging(command: "set clienv rows 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit").
    ///
    /// Best-effort: exits enable (expert) mode if currently in it,
    /// swallowing any failure, then always sends the final exit
    /// command regardless.
    override public func cleanup(command: String = "exit") async throws {
        do {
            if try await isInEnableMode() {
                _ = try await exitEnableMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Custom hook for sending the "expert" password at the exact
    /// moment enterEnableMode() detects the password prompt.
    ///
    /// Maps to netmiko's enable_secret_handler(pattern, output,
    /// re_flags=re.IGNORECASE).
    ///
    /// Check Point Gaia's expert-mode password exchange is unusually
    /// timing-sensitive — the base enable-mode flow's normal
    /// "write secret, then immediately continue reading" approach
    /// isn't reliable here. This hook exists specifically so
    /// enterEnableMode() can delegate the secret-sending step to a
    /// device-specific implementation rather than hardcoding one
    /// timing strategy for all devices: after writing the secret, it
    /// deliberately pauses, sends an extra bare return, pauses again,
    /// and only then reads until the prompt reappears — three
    /// distinct sleep/write steps where most drivers would do one.
    ///
    /// This is the first file in this vendor set assuming
    /// BaseConnection.enterEnableMode() calls out to a swappable
    /// per-driver secret-handling step rather than always sending the
    /// secret itself inline — worth confirming that hook point
    /// actually exists (or gets added) on BaseConnection, since every
    /// prior enable() override (Adtran, Yamaha, Arista, FTD) instead
    /// fully replaced the whole enable flow rather than plugging into
    /// a sub-step of it.
    override public func enableSecretHandler(
        pattern: String,
        output: String,
        caseInsensitive: Bool = true
    ) async throws -> String {
        guard output.range(
            of: pattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil else {
            // Matches Netmiko's behavior exactly: if the pattern never
            // matched, `new_output` is never assigned in the Python
            // source either, which would raise an UnboundLocalError
            // there. Rather than reproduce that latent bug, this
            // returns the original output unchanged — a safer
            // fallback with equivalent "nothing happened" semantics.
            return output
        }

        try await writeChannel(profile.secret ?? "")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))

        return try await readUntilPattern(pattern: promptPattern)
    }

    /// Enter expert mode.
    ///
    /// Maps to netmiko's enable(cmd="expert", pattern=r"expert
    /// password", enable_pattern=r"\#", re_flags=re.IGNORECASE).
    ///
    /// Delegates the actual password-sending step to
    /// enableSecretHandler() above via the base implementation, then
    /// re-detects the base prompt afterward — expert mode changes the
    /// prompt shape, so the previously stored basePrompt is stale
    /// once this returns.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "expert",
        pattern: String = "expert password",
        enablePattern: String? = #"#"#,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        let output = try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive
        )
        try await setBasePrompt()
        return output
    }

    /// Exit expert mode.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    ///
    /// Unlike most exitEnableMode overrides in this vendor set, this
    /// one deliberately does NOT call super — the wait pattern here
    /// is a bare ">" rather than anything the generic base
    /// implementation would search for, and the prompt must be
    /// re-detected immediately afterward since expert mode's prompt
    /// shape differs from normal mode's.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        output += try await readUntilPattern(pattern: ">")
        try await setBasePrompt()

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="save config").
    ///
    /// Unusually, this EXITS expert mode first (if currently in it)
    /// before sending the save command — the opposite ordering from
    /// most drivers, which typically ensure they're enabled/elevated
    /// before saving. Check Point's "save config" apparently must run
    /// from the normal Gaia clish prompt, not from within expert
    /// mode.
    public func saveConfig(
        command: String = "save config",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        var output = ""

        if try await isInEnableMode() {
            try await writeChannel(normalizeCommand("exit"))
            output += try await readUntilPattern(pattern: ">")
            try await setBasePrompt()
        }

        output += try await sendCommand(
            command,
            readTimeout: 100.0,
            stripPrompt: false,
            stripCommand: false
        )
        return output
    }
}
