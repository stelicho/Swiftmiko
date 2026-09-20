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
// Sources/Swiftmiko/Huawei/Huawei.swift

import Foundation

/// Common implementation for standard Huawei VRP devices (both SSH
/// and Telnet).
///
/// Maps to netmiko's HuaweiBase(NoEnable, CiscoBaseConnection).
///
/// No privilege escalation on this platform — hence NoEnable.
/// "Enable mode" here means Huawei's system-view, similar in spirit
/// to Comware's aliasing, though this file doesn't go as far as
/// literally forwarding enable() to config_mode() the way Comware
/// does.
open class HuaweiBase: CiscoBaseConnection, NoEnable {

    override public nonisolated var promptPattern: String { #"[\]>]"# }

    /// Shared pattern fragments used across the login-handling
    /// subclasses below.
    /// Maps to netmiko's class-level password_change_prompt and
    /// prompt_or_password_change.
    internal nonisolated var passwordChangePrompt: String {
        "(?:Change now|Please choose)"
    }
    internal nonisolated var promptOrPasswordChange: String {
        "(?:Change now|Please choose|\(promptPattern))"
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — deliberately
    /// minimal, since the actual initial channel read happens inside
    /// specialLoginHandler()/telnetLogin() instead.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await setBasePrompt()
        try await disablePaging(command: "screen-length 0 temporary")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: ANSI Handling

    /// Same cursor-left escape stripping as HuaweiSmartAXSSH — see
    /// that file's comment for the full explanation.
    /// Maps to netmiko's strip_ansi_escape_codes() override.
    override public func stripAnsiEscapeCodes(_ input: String) -> String {
        let cursorLeftCode = "\u{1B}" + #"\[\d+D"#
        let pattern = " " + cursorLeftCode
        let output = input.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
        return super.stripAnsiEscapeCodes(output)
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="system-view").
    @discardableResult
    override public func enterConfigMode(
        command: String = "system-view",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(command: command, pattern: pattern)
    }

    /// Maps to netmiko's exit_config_mode(exit_config="return",
    /// pattern=r">").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "return",
        pattern: String = ">"
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig, pattern: pattern)
    }

    /// Maps to netmiko's check_config_mode(check_string="]") — note
    /// this drops the `pattern` argument when forwarding to super,
    /// same recurring "accepted but not forwarded" quirk seen on
    /// Calix B6, Fiberstore NetworkOS, and FlexVNF.
    override public func isInConfigMode(
        checkString: String = "]",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(checkString: checkString)
    }

    // MARK: Prompt Detection

    /// Detect the base prompt, stripping the leading bracket/angle
    /// delimiter and any HA-cluster hostname prefix.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator="]") — near-identical logic to
    /// HPComwareBase.setBasePrompt(), but stripping a different HA
    /// prefix ("HRP_." for Huawei's USGv5 firewall HA, vs. Comware's
    /// "RBM_.").
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = "]",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )

        var prompt = basePrompt.replacingOccurrences(
            of: #"^HRP_."#,
            with: "",
            options: [.regularExpression]
        )
        if !prompt.isEmpty {
            prompt = String(prompt.dropFirst())
        }
        basePrompt = prompt.trimmingCharacters(in: .whitespaces)
        logger.debug("prompt: \(basePrompt)")
    }

    // MARK: Save Config

    /// Save the running configuration, handling either of two known
    /// confirmation banner shapes Huawei devices present.
    ///
    /// Maps to netmiko's save_config(cmd="save", confirm=true,
    /// confirm_response="y").
    ///
    /// Netmiko's own docstring documents both possible confirmation
    /// banner variants Huawei devices are known to present — worth
    /// keeping since it explains exactly what this method is
    /// defending against. Deliberately uses sendCommand rather than
    /// sendCommandTiming, per Netmiko's own comment that some Huawei
    /// devices "might break" if timing-based sends are used here.
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        var output: String
        if confirm {
            let pattern = "(?:[Cc]ontinue\\?|\(promptPattern))"
            output = try await sendCommand(
                command,
                readTimeout: 100.0,
                expectString: pattern,
                stripPrompt: false,
                stripCommand: false
            )
            if !confirmResponse.isEmpty,
               output.range(of: "[Cc]ontinue\\?", options: .regularExpression) != nil {
                output += try await sendCommand(
                    confirmResponse,
                    readTimeout: 100.0,
                    expectString: promptPattern,
                    stripPrompt: false,
                    stripCommand: false
                )
            }
        } else {
            output = try await sendCommand(
                command,
                readTimeout: 100.0,
                stripPrompt: false,
                stripCommand: false
            )
        }
        return output
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="quit").
    override public func cleanup(command: String = "quit") async throws {
        try await super.cleanup(command: command)
    }
}

// MARK: - HuaweiSSH

/// Huawei SSH driver.
///
/// Maps to netmiko's HuaweiSSH(HuaweiBase).
public class HuaweiSSH: HuaweiBase {

    /// Handle Huawei's optional password-change and
    /// secure-the-configuration prompts before the base prompt
    /// appears.
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// Two distinct interactive prompts are handled here, in
    /// sequence: a password-change nag (declined with "N"), and a
    /// "security risks in the configuration file" warning (accepted
    /// with "Y" twice — once to continue, once to actually save —
    /// then waited on for up to 60 seconds for a "saved successfully"
    /// confirmation before proceeding).
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let data = try await readUntilPattern(pattern: promptOrPasswordChange)

        if data.range(of: passwordChangePrompt, options: .regularExpression) != nil {
            try await writeChannel("N" + profile.returnCharacter)
            _ = try await readUntilPattern(pattern: promptPattern)
        }

        if data.range(
            of: #"security\srisks\sin\sthe\sconfiguration\sfile.*\[y\/n\]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            _ = try await sendCommand("Y", expectString: "(?i)continue.*\\[y\\/n\\]")
            _ = try await sendCommand("Y", expectString: "saved\\ssuccessfully", readTimeout: 60)
            _ = try await readUntilPattern(pattern: promptPattern)
        }
    }
}

// MARK: - HuaweiTelnet

/// Huawei Telnet driver.
///
/// Maps to netmiko's HuaweiTelnet(HuaweiBase).
///
/// Fully custom telnetLogin() — note the password is sent with a
/// bare "\r" rather than the profile's configured return character,
/// per Netmiko's own comment that Huawei "might require only \r for
/// password to be accepted."
public final class HuaweiTelnet: HuaweiBase {

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
                    "Huawei requires password authentication"
                )
            }
            // Huawei might require only "\r" for the password to be
            // accepted, rather than the profile's normal return
            // character.
            try await writeChannel(password + "\r")

            output = try await readUntilPattern(pattern: promptOrPasswordChange)
            returnMsg += output

            if output.range(of: passwordChangePrompt, options: .regularExpression) != nil {
                try await writeChannel("N" + telnetReturn)
                output = try await readUntilPattern(pattern: promptPattern)
                returnMsg += output
                return returnMsg
            } else if output.range(of: promptPattern, options: .regularExpression) != nil {
                return returnMsg
            }

            throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
        } catch {
            await closeTransport()
            throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
        }
    }
}

// MARK: - HuaweiVrpv8SSH

/// Huawei VRPv8 SSH driver, adding a commit-based configuration
/// lifecycle on top of the standard Huawei SSH driver.
///
/// Maps to netmiko's HuaweiVrpv8SSH(HuaweiSSH).
public final class HuaweiVrpv8SSH: HuaweiSSH {

    /// Maps to netmiko's send_config_set(), forwarded with
    /// exitConfigMode defaulted to false — VRPv8 requires the session
    /// to remain in config mode after a command set, same
    /// requirement as Cisco XR, CDOT CROS, and Ericsson IPOS.
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
        return try await super.sendConfigSet(commands, exitConfigMode: exitConfigMode)
    }

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(comment="", read_timeout=120.0).
    @discardableResult
    public func commit(
        comment: String = "",
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        let errorMarker = "Failed to generate committed config"
        var commandString = "commit"

        if !comment.isEmpty {
            commandString += " comment \"\(comment)\""
        }

        var output = try await enterConfigMode()
        output += try await sendCommand(
            commandString,
            readTimeout: readTimeout,
            expectString: "]",
            stripPrompt: false,
            stripCommand: false
        )
        output += try await exitConfigMode()

        guard !output.contains(errorMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with following errors:\n\n\(output)"
            )
        }
        return output
    }
}
