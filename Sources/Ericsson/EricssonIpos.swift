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
// Sources/Swiftmiko/Ericsson/EricssonIpos.swift

import Foundation

/// Ericsson IPOS SSH driver (originally RedBack equipment, per
/// Netmiko's own comment).
///
/// Maps to netmiko's EricssonIposSSH(BaseConnection).
public final class EricssonIposSSH: BaseConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await setTerminalWidth(command: "terminal width 512", pattern: "terminal")
        try await disablePaging()
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Maps to netmiko's enable(cmd="enable 15", pattern="ssword",
    /// re_flags=re.IGNORECASE). Note "enable 15" specifically — a
    /// RedBack/IPOS-style privilege LEVEL argument, not a bare
    /// "enable" command.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable 15",
        pattern: String = "ssword",
        enablePattern: String? = nil,
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

    /// Maps to netmiko's exit_enable_mode(exit_command="disable").
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "disable"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="configure").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Exit configuration mode.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="end",
    /// pattern="#"). Netmiko's own comment is worth preserving:
    /// unlike most devices where "end"/"exit" simply leaves config
    /// mode, Ericsson's own CLI help text describes "end" as
    /// "Commit configuration changes and return to exec mode" —
    /// meaning this exit command has a real side effect (an implicit
    /// commit), not just a mode transition.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = "#"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Config Set

    /// Maps to netmiko's send_config_set(), forwarded with
    /// exitConfigMode defaulted to false — Ericsson IPOS requires the
    /// session to remain in config mode after a command set, same
    /// requirement as Cisco XR and CDOT CROS.
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
        return try await super.sendConfigSet(
            commands,
            exitConfigMode: exitConfigMode,
            readTimeout: readTimeout,
            maxLoops: maxLoops,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            configModeCommand: configModeCommand,
            cmdVerify: cmdVerify,
            enterConfigMode: enterConfigMode,
            errorPattern: errorPattern,
            terminator: terminator,
            bypassCommands: bypassCommands
        )
    }

    // MARK: Save Config

    /// Save the running configuration, with an optional confirmation
    /// step.
    ///
    /// Maps to netmiko's save_config(cmd="save config", confirm=true,
    /// confirm_response="yes").
    public func saveConfig(
        command: String = "save config",
        confirm: Bool = true,
        confirmResponse: String = "yes"
    ) async throws -> String {
        var output = ""
        if confirm {
            output += try await sendCommandTiming(
                command,
                stripPrompt: false,
                stripCommand: false
            )
            if !confirmResponse.isEmpty {
                output += try await sendCommandTiming(
                    confirmResponse,
                    stripPrompt: false,
                    stripCommand: false
                )
            } else {
                output += try await sendCommandTiming(
                    profile.returnCharacter,
                    stripPrompt: false,
                    stripCommand: false
                )
            }
        } else {
            output += try await sendCommand(
                command,
                stripPrompt: false,
                stripCommand: false
            )
        }
        return output
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(confirm=false, confirm_delay=None,
    /// comment="", read_timeout=120.0).
    ///
    /// Structurally very close to Juniper's commit() and CDOT CROS's
    /// commit() — confirm/confirmDelay/comment combination, a fixed
    /// success marker to check for, automatic config-mode entry and
    /// exit around the commit itself.
    @discardableResult
    public func commit(
        confirm: Bool = false,
        confirmDelay: Int? = nil,
        comment: String = "",
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        guard !(confirmDelay != nil && !confirm) else {
            throw SwiftmikoError.invalidArgument(
                "Invalid arguments supplied to commit method both confirm and check"
            )
        }

        var commandString = "commit"
        var commitMarker = "Transaction committed"

        if confirm {
            if let confirmDelay {
                commandString = "commit confirmed \(confirmDelay)"
            } else {
                commandString = "commit confirmed"
            }
            commitMarker = "Commit confirmed ,it will be rolled back within"
        }

        if !comment.isEmpty {
            guard !comment.contains("\"") else {
                throw SwiftmikoError.invalidArgument(
                    "Invalid comment contains double quote"
                )
            }
            commandString += " comment \"\(comment)\""
        }

        var output = try await enterConfigMode()
        output += try await sendCommand(
            commandString,
            readTimeout: readTimeout,
            stripPrompt: false,
            stripCommand: false
        )

        guard output.contains(commitMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }

        _ = try await exitConfigMode()
        return output
    }
}
