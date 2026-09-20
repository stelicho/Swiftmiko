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
// Sources/Swiftmiko/Dell/DellPowerConnect.swift

import Foundation

/// Common implementation for Dell PowerConnect switches.
///
/// Maps to netmiko's DellPowerConnectBase(CiscoBaseConnection).
///
/// Notably disables paging TWICE with two different commands in a
/// row — "terminal datadump" for the Dell 34xx line and "terminal
/// length 0" for the Dell 7xxx line. Rather than detecting the model
/// first, this just fires both; whichever command the connected
/// model doesn't recognize presumably fails harmlessly (an
/// "unrecognized command" response) while the correct one succeeds.
open class DellPowerConnectBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "terminal datadump")  // Dell 34xx
        try await disablePaging(command: "terminal length 0")  // Dell 7xxx
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator="#").
    override public func setBasePrompt(
        primaryTerminator: String = ">",
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
        basePrompt = basePrompt.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Config Mode

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

    /// Maps to netmiko's config_mode(config_command="config").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }
}

// MARK: - DellPowerConnectSSH

/// Dell PowerConnect SSH driver.
///
/// Maps to netmiko's DellPowerConnectSSH(DellPowerConnectBase).
///
/// Netmiko's own docstring: "To make it work, we have to override the
/// SSHClient _auth method. If we use login/password, the ssh server
/// use the (none) auth mechanism." Same no-auth transport requirement
/// as SG200 and Calix B6 — this is now the third driver hitting the
/// same architectural gap flagged at Calix B6.
public final class DellPowerConnectSSH: DellPowerConnectBase {

    /// Maps to netmiko's _get_ssh_client_instance().
    /// See the no-auth transport gap discussion in CalixB6.swift.
    internal func requiresNoAuthTransport() -> Bool {
        switch profile.auth {
        case .keyFile, .sshAgent:
            return false
        case .password, .none:
            return true
        }
    }

    /// Handle PowerConnect's login banner sequence:
    ///
    ///     User Name:
    ///
    ///     Password: ****
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// Structurally identical to Calix B6's login handler — poll for
    /// data, respond to labeled prompts, nudge with a bare return if
    /// nothing arrives, bounded by a fixed iteration count (13
    /// attempts here) rather than a wall-clock timeout.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let resolvedDelay = selectDelayFactor(delay)
        try await Task.sleep(nanoseconds: UInt64(resolvedDelay * 0.5 * 1_000_000_000))

        for _ in 0...12 {
            let output = try await readChannel()
            if !output.isEmpty {
                if output.contains("User Name:") {
                    try await writeChannel(profile.username + profile.returnCharacter)
                } else if output.contains("Password:") {
                    guard case .password(let password) = profile.auth else {
                        throw SwiftmikoError.authenticationFailed(
                            "Dell PowerConnect requires password authentication"
                        )
                    }
                    try await writeChannel(password + profile.returnCharacter)
                    return
                }
                try await Task.sleep(nanoseconds: UInt64(resolvedDelay * 1.0 * 1_000_000_000))
            } else {
                try await writeChannel(profile.returnCharacter)
                try await Task.sleep(nanoseconds: UInt64(resolvedDelay * 1.5 * 1_000_000_000))
            }
        }
    }
}

// MARK: - DellPowerConnectTelnet

/// Dell PowerConnect Telnet driver — no differences from the base.
/// Maps to netmiko's DellPowerConnectTelnet(DellPowerConnectBase).
public final class DellPowerConnectTelnet: DellPowerConnectBase {}
