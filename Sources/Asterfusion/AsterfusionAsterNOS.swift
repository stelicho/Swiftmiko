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
// Sources/Swiftmiko/Asterfusion/AsterfusionAsterNOS.swift

import Foundation

/// The CLI shell to land in on Asterfusion AsterNOS devices.
///
/// Maps to netmiko's `_cli_mode` constructor parameter, which accepts
/// a bare string ("klish" or "bash") in Python. Modeled as an enum
/// here since the set of valid values is small, fixed, and known at
/// compile time — an invalid string typo in Python would silently
/// fall through to neither branch in session_preparation(); an
/// invalid case here is a compile error instead.
public enum AsterfusionCLIMode: Sendable {
    case klish
    case bash
}

/// Asterfusion AsterNOS SSH driver.
///
/// AsterNOS runs Enterprise SONiC underneath, meaning the device is
/// genuinely Linux at its core. It exposes multiple distinct
/// interactive shells over the same SSH session:
///
///   - klish   A traditional network-CLI-style shell (the default),
///             entered via "sonic-cli"
///   - bash    A raw Bash shell, entered via "system bash"
///   - vtysh   FRRouting's routing-protocol shell, entered via
///             "vtysh" — reachable via enterVtysh() but not selected
///             automatically by any cliMode value; the caller must
///             invoke it directly after connecting
///
/// Maps to netmiko's AsterfusionAsterNOSSSH(NoEnable,
/// CiscoSSHConnection). No privilege escalation on this platform —
/// hence NoEnable.
public final class AsterfusionAsterNOSSSH: CiscoSSHConnection, NoEnable {

    override public nonisolated var promptPattern: String { #"[>$#]"# }

    /// Which shell to enter during session preparation.
    /// Maps to netmiko's self._cli_mode, stored from the constructor
    /// argument of the same name.
    private let cliMode: AsterfusionCLIMode

    /// Maps to netmiko's __init__(_cli_mode="klish", **kwargs).
    public init(
        profile: ConnectionProfile,
        cliMode: AsterfusionCLIMode = .klish,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        self.cliMode = cliMode
        super.init(
            profile: profile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt(alt_prompt_terminator="$")
    ///     if self._cli_mode == "klish":
    ///         self._enter_shell()
    ///         self.disable_paging()
    ///     elif self._cli_mode == "bash":
    ///         self._enter_bash_cli()
    ///
    /// Note paging is only disabled in klish mode — a raw Bash shell
    /// has no concept of CLI pagination to turn off, so disablePaging
    /// is deliberately skipped in the bash branch.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt(altTerminator: "$")

        switch cliMode {
        case .klish:
            _ = try await enterShell()
            try await disablePaging()
        case .bash:
            _ = try await enterBashCLI()
        }
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="configure
    /// terminal", pattern=r"\#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure terminal",
        pattern: String = #"#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    // MARK: Shell Selection

    /// Enter the Klish-style network CLI (sonic-cli).
    /// Maps to netmiko's _enter_shell().
    /// Note: despite the generic name (matching Netmiko's own
    /// slightly misleading choice — this isn't a Bourne shell, unlike
    /// every other "_enter_shell" seen so far in this vendor set), this
    /// specifically enters the network-style klish CLI, not Bash.
    @discardableResult
    internal func enterShell() async throws -> String {
        return try await sendCommand("sonic-cli", expectString: #"#"#)
    }

    /// Enter the raw Bash shell.
    /// Maps to netmiko's _enter_bash_cli().
    @discardableResult
    internal func enterBashCLI() async throws -> String {
        return try await sendCommand("system bash", expectString: #"\$"#)
    }

    /// Enter FRRouting's vtysh shell.
    ///
    /// Maps to netmiko's _enter_vtysh().
    ///
    /// Unlike enterShell()/enterBashCLI(), this is never called from
    /// sessionPreparation() automatically — cliMode has no case that
    /// selects it. A caller who needs FRR-level routing commands must
    /// call this directly after connecting in either klish or bash
    /// mode. Carried over faithfully even though it's effectively
    /// unreachable through the normal connection flow, matching
    /// Netmiko's own apparent intent (this may be a helper for
    /// advanced/manual use rather than automatic session setup).
    @discardableResult
    internal func enterVtysh() async throws -> String {
        return try await sendCommand("vtysh", expectString: #"#"#)
    }

    // MARK: Paging

    /// Maps to netmiko's disable_paging(command="terminal
    /// raw-output").
    @discardableResult
    override public func disablePaging(
        command: String = "terminal raw-output",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.disablePaging(
            command: command,
            delay: delay,
            cmdVerify: cmdVerify,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write", confirm=true,
    /// confirm_response="y").
    override public func saveConfig(
        command: String = "write",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
