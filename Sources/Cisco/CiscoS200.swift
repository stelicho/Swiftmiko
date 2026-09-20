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
// Sources/Swiftmiko/Cisco/CiscoS200.swift

import Foundation

/// Common implementation for Cisco SG200 series switches (both SSH
/// and Telnet).
///
/// Maps to netmiko's CiscoS200Base(CiscoSSHConnection).
///
/// SG200 devices lack the `ip ssh password-auth` command that lets
/// most Cisco gear negotiate password auth through the standard SSH
/// exchange — Swiftmiko must handle authentication itself over a
/// no-auth SSH session instead, with specialLoginHandler() driving a
/// manual username/password prompt sequence.
open class CiscoS200Base: CiscoSSHConnection {

    /// Force multiline matching — SG200's prompt regex must anchor
    /// to end-of-line within a larger buffer, not end-of-string.
    override public nonisolated var promptPattern: String {
        #"(?m:[>#]\s*$)"#
    }

    // MARK: Transport Selection

    /// SG200 devices always require no-auth SSH authentication.
    ///
    /// Maps to netmiko's _get_ssh_client_instance().
    ///
    /// Same architectural gap noted for Calix B6: this reports
    /// *intent* rather than actually constructing a transport, since
    /// channel/transport selection happens outside BaseConnection in
    /// Swiftmiko's architecture (see the ChannelProvider discussion).
    /// Throws immediately if the caller's profile requests key- or
    /// agent-based auth, since neither is supported on this platform
    /// at all.
    internal func requiresNoAuthTransport() throws -> Bool {
        switch profile.auth {
        case .keyFile, .sshAgent:
            throw SwiftmikoError.invalidArgument(
                "Cisco SG200 does not support SSH key or agent authentication."
            )
        case .password, .none:
            return true
        }
    }

    // MARK: Login Handling

    /// Handle Cisco SG2xx's login banner sequence:
    ///
    ///     login as: user
    ///
    ///     Welcome to Layer 2 Managed Switch
    ///
    ///     Username: user
    ///     Password:****
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// Loops reading against a combined pattern matching any of the
    /// username/login/password prompts OR the final device prompt
    /// itself — once the device prompt appears, login is complete
    /// and the loop returns. Throws a detailed authentication error
    /// if none of the expected patterns ever appear within the
    /// timeout.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let usernameLabel = "Username:"
        let loginLabel = "login as"
        let passwordLabel = "ssword"
        let combinedPattern = "(?:\(usernameLabel)|\(loginLabel)|\(passwordLabel)|\(promptPattern))"

        var output = ""

        while true {
            let newData = try await readUntilPattern(
                pattern: combinedPattern,
                timeout: 25.0
            )
            output += newData

            if newData.range(of: promptPattern, options: .regularExpression) != nil {
                return
            }

            if newData.contains(usernameLabel) || newData.contains(loginLabel) {
                try await writeChannel(profile.username + profile.returnCharacter)
            } else if newData.contains(passwordLabel) {
                guard case .password(let password) = profile.auth else {
                    throw SwiftmikoError.authenticationFailed(
                        "Cisco SG2xx requires password authentication"
                    )
                }
                try await writeChannel(password + profile.returnCharacter)
            } else {
                throw SwiftmikoError.authenticationFailed(
                    """
                    Failed to login to Cisco SG2xx.

                    Pattern not detected: \(combinedPattern)
                    output:

                    \(output)

                    """
                )
            }
        }
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="terminal length 0")
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "terminal length 0")
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory", confirm=true,
    /// confirm_response="Y").
    override public func saveConfig(
        command: String = "write memory",
        confirm: Bool = true,
        confirmResponse: String = "Y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

// MARK: - CiscoS200SSH

/// Cisco SG200 SSH driver — no differences from the base.
/// Maps to netmiko's CiscoS200SSH(CiscoS200Base).
public final class CiscoS200SSH: CiscoS200Base {}

// MARK: - CiscoS200Telnet

/// Cisco SG200 Telnet driver — no differences from the base.
/// Maps to netmiko's CiscoS200Telnet(CiscoS200Base).
public final class CiscoS200Telnet: CiscoS200Base {}
