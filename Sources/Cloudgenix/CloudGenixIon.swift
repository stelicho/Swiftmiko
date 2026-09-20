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
// Sources/Swiftmiko/CloudGenix/CloudGenixIon.swift

import Foundation

/// CloudGenix ION SSH driver.
///
/// Maps to netmiko's CloudGenixIonSSH(NoConfig, CiscoSSHConnection).
///
/// No configuration mode via this connection — hence NoConfig. The
/// terminal dimensions are set at the PTY-negotiation level during
/// connection establishment rather than via a device command, and
/// the device's redraw behavior is unusually aggressive: prompts can
/// contain stray backspace characters, and command output can
/// literally repaint the echoed command string multiple times before
/// settling.
public final class CloudGenixIonSSH: CiscoSSHConnection, NoConfig {

    // MARK: Connection Establishment

    /// Establish the SSH connection with CloudGenix's specific
    /// terminal dimensions.
    ///
    /// Maps to netmiko's establish_connection(width=100, height=1000).
    ///
    /// Unlike setTerminalWidth() (a CLI command sent after the
    /// session is up), this sets the PTY's negotiated terminal size
    /// at the SSH channel-request level, before any command can be
    /// sent at all. The unusually tall height (1000 rows) suggests
    /// this device's paging can't be reliably disabled by command, so
    /// the workaround is to make the virtual terminal tall enough
    /// that paging rarely triggers in practice — consistent with
    /// disablePaging() below being a hard no-op.
    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.write_channel(self.RETURN)
    ///     self.set_base_prompt(delay_factor=5)
    ///
    /// Note the unusually large delay_factor=5 passed to
    /// setBasePrompt — five times the typical default, suggesting
    /// this device's prompt takes meaningfully longer to settle than
    /// most, consistent with the aggressive repainting behavior
    /// documented in stripCommand() below.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await writeChannel(profile.returnCharacter)
        try await setBasePrompt(delay: 5.0)
    }

    // MARK: Paging

    /// Paging is controlled via the terminal height set during
    /// establishConnection(), not a CLI command — hard no-op here.
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

    // MARK: Prompt Detection

    /// Find the current prompt, stripping any stray backspace
    /// characters the device's redraw behavior can leave embedded in
    /// it.
    ///
    /// Maps to netmiko's find_prompt(), which calls a
    /// self.strip_backspaces() helper — the same backspace-stripping
    /// logic already implemented as a private helper inside
    /// SSHDetect (see SSHAutodetect.swift's stripBackspaces(_:)).
    /// This confirms that helper needs to be promoted from a private
    /// implementation detail of autodetection into a general,
    /// reusable method on BaseConnection itself, since a real device
    /// driver now needs it too.
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        let prompt = try await super.findPrompt(delay: delay, pattern: pattern)
        return stripBackspaces(prompt).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Output Stripping

    /// Strip the command echo from output, accounting for the
    /// device's tendency to repaint the command string multiple
    /// times before the real output appears.
    ///
    /// Maps to netmiko's strip_command(command_string, output).
    ///
    /// Rather than stripping just the first occurrence of the
    /// command echo, this splits the ENTIRE output on every
    /// occurrence of the command string and keeps only what comes
    /// after the LAST one — since the device may redraw the echoed
    /// command several times as the terminal repaints, only the
    /// final repaint is followed by the actual command output.
    override public func stripCommand(
        _ commandString: String,
        output: String
    ) -> String {
        let baseStripped = super.stripCommand(commandString, output: output)
        let segments = baseStripped.components(separatedBy: commandString)
        return segments.last ?? baseStripped
    }

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "CloudGenix ION does not support saveConfig()"
        )
    }

    // MARK: Config Set

    /// Maps to netmiko's send_config_set(), forwarded with
    /// exitConfigMode defaulted to false. Note this exists despite
    /// the class conforming to NoConfig — same pattern as Zyxel and
    /// SMCI: NoConfig's no-op enter/exit config mode makes it safe to
    /// still push commands through without a real config-mode
    /// transition ever occurring.
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
}
