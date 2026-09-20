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
// Sources/Swiftmiko/Huawei/HuaweiOnt.swift

import Foundation

/// Common implementation for Huawei ONT (Optical Network Terminal)
/// devices.
///
/// Maps to netmiko's HuaweiONTBase(NoConfig, CiscoBaseConnection).
///
/// No configuration mode on this platform — all changes are
/// immediate, hence NoConfig, and saveConfig() is a hard error rather
/// than a no-op, making that fact impossible to miss. "Enable mode"
/// here means becoming super user ("su"), landing at a distinctly
/// prefixed prompt ("SU_WAP>") rather than the base "WAP>".
open class HuaweiONTBase: CiscoBaseConnection, NoConfig {

    override public nonisolated var promptPattern: String { "WAP>" }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — deliberately minimal,
    /// since the actual channel-ready check happens inside
    /// specialLoginHandler()/telnetLogin() instead.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await setBasePrompt()
    }

    // MARK: Save Config

    /// Not supported — Huawei ONTs apply every change immediately,
    /// with no save step at all.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Save config is not supported on Huawei ONTs."
        )
    }

    // MARK: Enable Mode

    /// Check if the device is in su (super user) mode.
    /// Maps to netmiko's check_enable_mode(check_string="SU_WAP>").
    override public func isInEnableMode(
        checkString: String = "SU_WAP>"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Attempt to become super user.
    /// Maps to netmiko's enable(cmd="su", enable_pattern=r"SU_WAP>",
    /// re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "su",
        pattern: String = "",
        enablePattern: String? = "SU_WAP>",
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        return try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive
        )
    }

    /// Exit super user mode.
    /// Maps to netmiko's exit_enable_mode(exit_command="quit").
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "quit"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="logout").
    override public func cleanup(command: String = "logout") async throws {
        try await super.cleanup(command: command)
    }
}

// MARK: - HuaweiONTSSH

/// Huawei ONT SSH driver — no differences from the base.
/// Maps to netmiko's HuaweiONTSSH(HuaweiONTBase).
public final class HuaweiONTSSH: HuaweiONTBase {}

// MARK: - HuaweiONTTelnet

/// Huawei ONT Telnet driver.
///
/// Maps to netmiko's HuaweiONTTelnet(HuaweiONTBase).
///
/// Fully custom telnetLogin() rather than a parameter forward — the
/// generic base implementation isn't reused at all here. On failure
/// (no prompt ever appears within the expected sequence), this
/// closes the raw transport and throws, same "clean up before
/// failing" discipline as Fiberstore FSOS's auth-failure path.
public final class HuaweiONTTelnet: HuaweiONTBase {

    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = "",
        altTerminator: String = "",
        usernamePattern: String = "(?:user:|username|login|Login|user name)",
        passwordPattern: String = "Password:|password:",
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
                    "Huawei ONT requires password authentication"
                )
            }
            try await writeChannel(password + telnetReturn)

            output = try await readUntilPattern(pattern: promptPattern)
            returnMsg += output

            guard output.range(of: promptPattern, options: .regularExpression) != nil else {
                // Should never reach here — mirrors Netmiko's own
                // "raise EOFError" fallthrough for an unexpected state.
                throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
            }
            return returnMsg
        } catch {
            await closeTransport()
            throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
        }
    }
}
