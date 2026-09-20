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
// Sources/Swiftmiko/TerminalServer/TerminalServer.swift

import Foundation

/// Generic Terminal Server driver.
/// Allows direct writeChannel / readChannel operations without
/// sessionPreparation causing an exception.
///
/// Maps to netmiko's TerminalServer(BaseConnection).
open class TerminalServer: BaseConnection {

    /// No-op: base_prompt is not set; paging is not disabled.
    override public func sessionPreparation() async throws {
        // Intentional no-op — terminal servers bypass all setup.
    }
}

/// Generic Terminal Server SSH driver.
/// Maps to netmiko's TerminalServerSSH(TerminalServer).
public final class TerminalServerSSH: TerminalServer {}

/// Generic Terminal Server Telnet driver.
/// Maps to netmiko's TerminalServerTelnet(TerminalServer).
///
/// Disables automatic username/password handling by returning
/// immediately from telnetLogin — the caller manages the session
/// directly via read/write channel.
public final class TerminalServerTelnet: TerminalServer {

    /// Disable automatic handling of username and password.
    /// Maps to netmiko's telnet_login() override that returns "".
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(?:username|login)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        return ""
    }

    /// Expose the base class login handler for callers that need it.
    @discardableResult
    public func stdLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(?:username|login)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        return try await super.telnetLogin(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            usernamePattern: usernamePattern,
            passwordPattern: passwordPattern,
            delay: delay,
            maxLoops: maxLoops
        )
    }
}
