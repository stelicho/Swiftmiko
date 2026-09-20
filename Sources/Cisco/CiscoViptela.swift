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
//
//  CiscoViptela.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//
// Sources/Swiftmiko/Cisco/CiscoViptela.swift

import Foundation
import Logging

/// Cisco Viptela (SD-WAN) SSH driver.
///
/// Maps to netmiko's CiscoViptelaSSH(CiscoSSHConnection).
///
/// Differences from CiscoSSHConnection defaults:
///   1. Paging disabled with "paginate false" instead of "terminal length 0"
///   2. Config mode entered with "conf terminal", not "configure terminal"
///   3. sendConfigSet() does NOT exit config mode by default
///   4. exitConfigMode() handles uncommitted changes interactively
///   5. saveConfig() is not supported — use commit() instead
public final class CiscoViptelaSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        // Difference 1: Viptela's paging command is "paginate false"
        try await disablePaging(command: "paginate false")
    }

    // MARK: Config Mode

    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "#"
    ) async throws -> Bool {
        // check_string stays ")#" but pattern narrows to "#" only —
        // Viptela doesn't use ">" at the config level
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Enter configuration mode.
    ///
    /// Difference 2: Viptela uses "conf terminal" (abbreviated form).
    /// The base class default is "configure terminal".
    @discardableResult
    override public func enterConfigMode(
        command: String = "conf terminal",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    /// Send a set of configuration commands.
    ///
    /// Difference 3: exitConfigMode defaults to FALSE on Viptela.
    /// Viptela requires an explicit commit() before changes take effect.
    /// Automatically exiting config mode before commit would discard changes.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = false,      // <-- false, not true
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

    /// Exit configuration mode, handling uncommitted changes.
    ///
    /// Difference 4: Viptela may prompt:
    ///     "Uncommitted changes found, commit them? [yes/no/CANCEL]"
    ///
    /// Netmiko's policy (which we mirror) is to answer "no" — discard
    /// uncommitted changes and exit cleanly. The caller is responsible
    /// for calling commit() before exitConfigMode() if they want to save.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = "#"
    ) async throws -> String {
        guard try await isInConfigMode() else { return "" }

        try await writeChannel(normalizeCommand(exitConfig))

        // Wait for command echo to avoid getting out of sync with the channel
        if cmdVerifyEnabled {
            _ = try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(for: exitConfig.trimmingCharacters(in: .whitespaces))
            )
        }

        // Check if we landed at the prompt or hit the uncommitted changes question
        let uncommittedPattern = "Uncommitted changes found"
        let combinedPattern = "(\(pattern)|\(uncommittedPattern))"
        var output = try await readUntilPattern(pattern: combinedPattern)

        if output.contains(uncommittedPattern) {
            // Answer "no" — discard changes, do not commit automatically
            try await writeChannel(normalizeCommand("no"))
            output += try await readUntilPattern(pattern: pattern)
        }

        if try await isInConfigMode() {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }

        return output
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Viptela uses a two-phase commit model — config commands stage changes,
    /// commit() makes them active. Maps to netmiko's commit() which calls
    /// super().save_config(cmd="commit").
    public func commit(
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: "commit",
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Save Config

    /// Not supported on Viptela — use commit() instead.
    ///
    /// Maps to netmiko's: raise NotImplementedError
    override public func saveConfig(
        command: String = "commit",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "CiscoViptela does not use saveConfig() — call commit() instead"
        )
    }
}
