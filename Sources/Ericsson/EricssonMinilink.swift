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
// Sources/Swiftmiko/Ericsson/EricssonMinilink.swift

import Foundation

/// Common implementation for Ericsson MiniLink devices.
///
/// Maps to netmiko's EricssonMinilinkBase(NoEnable, BaseConnection).
///
/// No privilege escalation on this platform — hence NoEnable.
/// MiniLink uses a genuinely unusual two-tier authentication model:
/// the SSH transport layer itself always authenticates as the fixed
/// user "cli" (possibly a shared account required by the device's
/// firmware), while the REAL username is only ever used later, at
/// the application-level login prompt handled inside
/// specialLoginHandler(). This is the first driver in this vendor set
/// where the SSH-layer identity and the CLI-layer identity are
/// deliberately different.
open class EricssonMinilinkBase: BaseConnection, NoEnable {

    override public nonisolated var promptPattern: String { "[>#]" }

    /// The real username to use at the CLI's application-level login
    /// prompt, separate from the fixed "cli" identity used for the
    /// SSH transport itself.
    ///
    /// Maps to netmiko's self._real_username, saved in __init__
    /// before the username kwarg is overwritten with "cli".
    private let realUsername: String

    /// Sets a default auth timeout and swaps in a fixed SSH-layer
    /// username, stashing the real one for later use in
    /// specialLoginHandler().
    ///
    /// Maps to netmiko's __init__ override:
    ///     if kwargs.get("auth_timeout") is None:
    ///         kwargs["auth_timeout"] = 20
    ///     self._real_username = ""
    ///     if "username" in kwargs:
    ///         self._real_username = kwargs["username"]
    ///         kwargs["username"] = "cli"
    ///     super().__init__(*args, **kwargs)
    ///     if self._real_username:
    ///         kwargs["username"] = self._real_username
    ///
    /// Note the final line in the Python — restoring kwargs["username"]
    /// AFTER super().__init__() has already run — appears to have no
    /// actual effect, since __init__ has already consumed kwargs by
    /// that point and self.username was already set from the
    /// "cli"-substituted value inside super().__init__(). This looks
    /// like a no-op or a latent bug in the original (perhaps intended
    /// to restore kwargs for some caller who inspects it afterward,
    /// but ineffective for anything self-referential). Not
    /// reproduced here since Swift's ConnectionProfile is a value
    /// type with no equivalent "the caller's dict is now stale"
    /// concept to preserve — this constructor's only real job is
    /// building the swapped profile and remembering the real
    /// username.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        self.realUsername = profile.username

        var adjustedProfile = profile
        adjustedProfile.username = "cli"
        if adjustedProfile.authTimeout == 0 {
            adjustedProfile.authTimeout = 20
        }

        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Transport Selection

    /// If not using SSH keys or agent, use noauth.
    /// Maps to netmiko's _get_ssh_client_instance().
    /// Same architectural gap as SG200/Calix B6/Dell PowerConnect.
    internal func requiresNoAuthTransport() -> Bool {
        switch profile.auth {
        case .keyFile, .sshAgent:
            return false
        case .password, .none:
            return true
        }
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation():
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt(pri_prompt_terminator="#",
    ///         alt_prompt_terminator=">", delay_factor=1)
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt(
            primaryTerminator: "#",
            altTerminator: ">",
            delay: 1.0
        )
    }

    // MARK: Login Handling

    /// Handle MiniLink's application-level CLI login, using the
    /// REAL username (not the "cli" SSH-layer identity) and the
    /// device's own password.
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// Presents as:
    ///     ------------------------------------------
    ///     MINI-LINK <model>  Command Line Interface
    ///     ------------------------------------------
    ///
    ///     Welcome to <hostname>
    ///     User:
    ///     Password:
    ///
    /// Polls for a combined username/password/"busy" pattern within
    /// authTimeout. A "busy" response means another session is
    /// already using the CLI — this immediately disconnects and
    /// throws rather than retrying, since a busy CLI is a different
    /// failure mode than a slow or unresponsive one.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let startTime = Date()
        var output = ""
        let timeout = profile.authTimeout

        let usernamePattern = "(?:login:|User:)"
        let passwordPattern = "ssword"
        let busyPattern = "busy"
        let combinedPattern = "(?:\(usernamePattern)|\(passwordPattern)|\(busyPattern))"

        while Date().timeIntervalSince(startTime) < timeout {
            let newOutput = try await readUntilPattern(
                pattern: combinedPattern,
                timeout: timeout
            )
            output += newOutput

            if newOutput.range(of: usernamePattern, options: .regularExpression) != nil {
                try await writeChannel(realUsername + profile.returnCharacter)
                continue
            } else if newOutput.range(of: passwordPattern, options: .regularExpression) != nil {
                guard case .password(let password) = profile.auth else {
                    throw SwiftmikoError.authenticationFailed(
                        "Ericsson MiniLink requires password authentication"
                    )
                }
                try await writeChannel(password + profile.returnCharacter)
                return
            } else if newOutput.range(of: busyPattern, options: .regularExpression) != nil {
                await disconnect()
                throw SwiftmikoError.connectionFailed("CLI is currently busy")
            }
        }

        throw SwiftmikoError.timeout(
            """
            Login process failed to device:
            Timeout reached (auth_timeout=\(timeout) seconds)
            """
        )
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="write").
    ///
    /// Note the unusual fixed "success" return value regardless of
    /// what the device actually said — this is faithfully carried
    /// over from Netmiko, but worth flagging as unusually weak error
    /// handling: a failed save that doesn't throw an exception along
    /// the way (e.g. a slow save that just times out silently at the
    /// sendCommand level) would still report "success" here.
    public func saveConfig(
        command: String = "write",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        if try await isInConfigMode() {
            _ = try await exitConfigMode()
        }
        _ = try await sendCommand(
            command,
            stripPrompt: false,
            stripCommand: false
        )
        return "success"
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="config",
    /// pattern=r"\(config\)#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = #"\(config\)#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's check_config_mode(check_string="(config)#").
    override public func isInConfigMode(
        checkString: String = "(config)#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit"). Same best-effort
    /// exit-config-mode-then-always-send-exit shape as Juniper and
    /// Check Point Gaia.
    override public func cleanup(command: String = "exit") async throws {
        do {
            if try await isInConfigMode() {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }
}

// MARK: - EricssonMinilink63SSH

/// Ericsson MiniLink 63XX SSH driver.
///
/// Maps to netmiko's EricssonMinilink63SSH(EricssonMinilinkBase).
public final class EricssonMinilink63SSH: EricssonMinilinkBase {

    /// The 63XX line uses "quit" rather than the base class's "exit"
    /// as its logout command.
    /// Maps to netmiko's cleanup(command="quit").
    override public func cleanup(command: String = "quit") async throws {
        try await super.cleanup(command: command)
    }
}

// MARK: - EricssonMinilink66SSH

/// Ericsson MiniLink 66XX SSH driver — no differences from the base.
/// Maps to netmiko's EricssonMinilink66SSH(EricssonMinilinkBase).
public final class EricssonMinilink66SSH: EricssonMinilinkBase {}
