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
// Sources/Swiftmiko/Calix/CalixB6.swift

import Foundation

/// Common implementation for Calix B6 devices (both SSH and Telnet).
///
/// Maps to netmiko's CalixB6Base(CiscoSSHConnection).
open class CalixB6Base: CiscoSSHConnection {

    /// Calix B6 requires "\r\n" as the line ending.
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
            adjustedProfile.returnCharacter = "\r\n"
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
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.set_terminal_width(command="terminal width 511", pattern="terminal")
    ///     self.disable_paging()
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await setTerminalWidth(command: "terminal width 511", pattern: "terminal")
        try await disablePaging()
    }

    // MARK: Login Handling

    /// Handle Calix B6's login banner sequence:
    ///
    ///     login as:
    ///     Password: ****
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// The polling structure here is distinct from the WLC/SG200
    /// special_login_handler pattern seen earlier: rather than
    /// looping on read_until_pattern with a single combined regex,
    /// this manually alternates between a quick poll and a longer
    /// sleep, nudging the connection with a bare return if a full
    /// poll cycle produces no data at all. That's a meaningfully
    /// different strategy worth preserving exactly rather than
    /// collapsing into the other pattern for consistency — Calix B6's
    /// login banner is apparently slow enough or intermittent enough
    /// that the original authors needed this specific retry shape.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        try await Task.sleep(nanoseconds: 100_000_000)
        let startTime = Date()
        let loginTimeout: TimeInterval = 20
        var newData = ""

        while Date().timeIntervalSince(startTime) < loginTimeout {
            let output: String
            if newData.isEmpty {
                output = try await readChannel()
            } else {
                output = newData
            }
            newData = ""

            if !output.isEmpty {
                if output.contains("login as:") {
                    try await writeChannel(profile.username + profile.returnCharacter)
                } else if output.contains("Password:") {
                    guard case .password(let password) = profile.auth else {
                        throw SwiftmikoError.authenticationFailed(
                            "Calix B6 requires password authentication"
                        )
                    }
                    try await writeChannel(password + profile.returnCharacter)
                    return
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            } else {
                // No new data — sleep longer before checking again.
                try await Task.sleep(nanoseconds: 500_000_000)
                newData = try await readChannel()
                // Still nothing — nudge the connection with a bare
                // return, same as Netmiko's fallback.
                if newData.isEmpty {
                    try await writeChannel(profile.returnCharacter)
                }
            }
        }

        throw SwiftmikoError.timeout(
            "Login process failed to Calix B6 device. Unable to log in " +
            "in \(Int(loginTimeout)) seconds."
        )
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#").
    /// Note: Netmiko's own override drops the `pattern` argument when
    /// calling super (an apparent oversight in the original, since
    /// `pattern` is accepted as a parameter but never forwarded) —
    /// preserved here exactly rather than "fixed", since changing
    /// this could alter matching behavior in ways that haven't been
    /// tested against a real device.
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(checkString: checkString)
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="copy run start").
    override public func saveConfig(
        command: String = "copy run start",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

// MARK: - CalixB6SSH

/// Calix B6 SSH driver.
///
/// Maps to netmiko's CalixB6SSH(CalixB6Base).
///
/// Netmiko's docstring here is important: "To make it work, we have
/// to override the SSHClient _auth method and manually handle the
/// username/password." Calix B6, like Cisco SG200, doesn't support
/// standard SSH password auth negotiation — when neither key-based
/// nor agent-based auth is requested, the connection must use a
/// no-auth SSH client and let specialLoginHandler() above handle
/// credentials manually over the plain channel instead of through
/// SSH's own auth exchange.
public final class CalixB6SSH: CalixB6Base {

    /// Selects a no-auth SSH client when neither keys nor agent auth
    /// were requested.
    ///
    /// Maps to netmiko's _get_ssh_client_instance().
    ///
    /// This is a transport-selection decision, not a channel I/O
    /// call — the actual `SSHClientNoAuth` type lives in
    /// SSHAuth.swift and expects an `SSHNoAuthTransport` to delegate
    /// to. Wiring this up fully depends on how the concrete SwiftNIO
    /// SSH transport is constructed elsewhere in Swiftmiko; this
    /// method signals the *intent* (use no-auth) which the connection
    /// factory / channel provider is responsible for honoring when
    /// actually opening the transport.
    internal func requiresNoAuthTransport() -> Bool {
        switch profile.auth {
        case .password:
            return true
        case .keyFile, .sshAgent, .none:
            return false
        }
    }
}

// MARK: - CalixB6Telnet

/// Calix B6 Telnet driver — no differences from the base.
/// Maps to netmiko's CalixB6Telnet(CalixB6Base).
public final class CalixB6Telnet: CalixB6Base {}
