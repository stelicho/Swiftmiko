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
// Sources/Swiftmiko/Fiberstore/FiberstoreFsos.swift

import Foundation

/// Fiberstore FSOS SSH driver (original FSOS, not V2).
///
/// Maps to netmiko's FiberstoreFsosSSH(NoEnable, CiscoBaseConnection).
///
/// FSOS uses a non-standard SSH login mechanism that requires
/// no-auth transport handling — same architectural gap as SG200,
/// Calix B6, Dell PowerConnect, and Ericsson MiniLink. No privilege
/// escalation on this platform — hence NoEnable.
public final class FiberstoreFsosSSH: CiscoBaseConnection, NoEnable {

    // MARK: Transport Selection

    /// If not using SSH keys or agent, use noauth.
    /// Maps to netmiko's _get_ssh_client_instance().
    internal func requiresNoAuthTransport() -> Bool {
        switch profile.auth {
        case .keyFile, .sshAgent:
            return false
        case .password, .none:
            return true
        }
    }

    // MARK: Session Preparation

    /// Prepare the session, actively detecting and rejecting a failed
    /// authentication banner.
    ///
    /// Maps to netmiko's session_preparation():
    ///     output = self._test_channel_read()
    ///     if "% Authentication Failed" in output:
    ///         self.remote_conn.close()
    ///         raise NetmikoAuthenticationException(...)
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="terminal length 0")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    ///
    /// Because FSOS's login mechanism is non-standard (routed through
    /// the no-auth SSH client above), a bad credential doesn't
    /// necessarily surface as a clean SSH-level auth failure — it can
    /// show up as banner TEXT in the channel instead. This check
    /// catches that case explicitly and closes the underlying
    /// transport before throwing, rather than leaving a half-open
    /// connection behind. `closeTransport()` here is expected to
    /// reach past the Channel abstraction to whatever raw connection
    /// object backs it — see the backlog note below on why this is
    /// worth confirming actually exists at that layer.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        let output = try await testChannelRead()

        if output.contains("% Authentication Failed") {
            await closeTransport()
            throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
        }

        try await setBasePrompt()
        try await disablePaging(command: "terminal length 0")
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

    // MARK: Login Handling

    /// Handle Fiberstore S3200's login sequence:
    ///
    ///     Username:
    ///     Password: ****
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// Bounded by a fixed iteration count (13 attempts, same as Dell
    /// PowerConnect's handler) rather than a wall-clock timeout —
    /// this is the second driver using exactly that bounded-loop
    /// shape, reinforcing it as a legitimate, recurring alternative
    /// to the wall-clock-deadline style used elsewhere (Calix B6,
    /// Extreme ERS).
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let resolvedDelay = selectDelayFactor(delay)

        for _ in 0...12 {
            try await Task.sleep(nanoseconds: UInt64(resolvedDelay * 1_000_000_000))
            let output = try await readChannel()
            guard !output.isEmpty else { continue }

            if output.contains("Username:") {
                try await writeChannel(profile.username + profile.returnCharacter)
            } else if output.contains("Password:") {
                guard case .password(let password) = profile.auth else {
                    throw SwiftmikoError.authenticationFailed(
                        "Fiberstore FSOS requires password authentication"
                    )
                }
                try await writeChannel(password + profile.returnCharacter)
                return
            }
        }
    }
}
