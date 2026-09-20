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
// Sources/Swiftmiko/Hioso/HiosoOlt.swift

import Foundation

/// Common implementation for Hioso OLT devices.
///
/// Maps to netmiko's HiosoOLTBase(CiscoBaseConnection).
///
/// Fairly similar to standard Cisco-family devices, per Netmiko's own
/// docstring — no mixin conformance (NoEnable/NoConfig) needed here,
/// unlike most OLT-family drivers in this vendor set.
open class HiosoOLTBase: CiscoBaseConnection {

    override public nonisolated var promptPattern: String { "[#>]" }

    /// Shared pattern fragment used by the Telnet login flow below.
    /// Maps to netmiko's class-level prompt_or_password_change.
    internal nonisolated var promptOrPasswordChange: String {
        "(?:Change now|Please choose|\(promptPattern))"
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging()
        try await clearBuffer()
        _ = try await exitEnableMode()
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern=r"[>#]").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern=r"#").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write file", confirm=false,
    /// confirm_response="y").
    override public func saveConfig(
        command: String = "write file",
        confirm: Bool = false,
        confirmResponse: String = "y"
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="quit").
    override public func cleanup(command: String = "quit") async throws {
        try await super.cleanup(command: command)
    }
}

// MARK: - HiosoOLTTelnet

/// Hioso OLT Telnet driver.
///
/// Maps to netmiko's HiosoOLTTelnet(HiosoOLTBase).
///
/// Fully custom telnetLogin() — three sequential interactive prompts
/// possible after the base username/password exchange:
///   1. A CLI-vs-Web management-mode selection menu ("Please choose
///      the management mode") — answered "1" to pick CLI.
///   2. A default-password-change nag ("Change now? [Y/N]") —
///      answered "N" to decline.
///   3. The real device prompt.
///
/// Both interactive steps are conditional — only handled if their
/// respective trigger text actually appears — and the method falls
/// through to a login-failure error (closing the transport first) if
/// none of the expected states are ever reached.
public final class HiosoOLTTelnet: HiosoOLTBase {

    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = "",
        altTerminator: String = "",
        usernamePattern: String = "(?:user:|username|login|user name)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        var returnMsg = ""

        do {
            var output = try await readUntilPattern(
                pattern: usernamePattern,
                caseInsensitive: true
            )
            returnMsg += output
            try await writeChannel(profile.username + telnetReturn)

            output = try await readUntilPattern(
                pattern: passwordPattern,
                caseInsensitive: true
            )
            returnMsg += output
            guard case .password(let password) = profile.auth else {
                throw SwiftmikoError.authenticationFailed(
                    "Hioso OLT requires password authentication"
                )
            }
            try await writeChannel(password + telnetReturn)

            // Wait for either the prompt or one of the two possible
            // interactive follow-up messages.
            output = try await readUntilPattern(pattern: promptOrPasswordChange)
            returnMsg += output

            // "Welcome to Hioso OLT. Please choose the management
            // mode (1: CLI, 2: Web Management Selection):" — pick CLI.
            if output.contains("Please choose") {
                try await writeChannel("1" + telnetReturn)
                output = try await readUntilPattern(pattern: promptOrPasswordChange)
                returnMsg += output
            }

            // "The current password is the default password. It is
            // recommended to change it for security. Change now?
            // [Y/N]" — decline.
            if output.contains("Change now") {
                try await writeChannel("N" + telnetReturn)
                output = try await readUntilPattern(pattern: promptPattern)
                returnMsg += output
            }

            guard output.range(of: promptPattern, options: .regularExpression) != nil else {
                // Should never reach here — mirrors Netmiko's own
                // "raise EOFError" fallthrough.
                throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
            }
            return returnMsg
        } catch {
            await closeTransport()
            throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
        }
    }
}
