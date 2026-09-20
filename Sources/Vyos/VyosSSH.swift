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
// Sources/Swiftmiko/Vyos/VyosSSH.swift

import Foundation

/// VyOS SSH driver.
///
/// Maps to netmiko's VyOSSSH(CiscoSSHConnection).
///
/// VyOS uses a commit-based configuration model. Config mode is
/// entered with "configure" and changes must be committed with
/// commit() before they take effect.
open class VyOSSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await setTerminalWidth(command: "set terminal width 512", pattern: "terminal")
        try await disablePaging(command: "set terminal length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Config Mode

    override public func isInConfigMode(
        checkString: String = "#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = #"\[edit\]"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        guard try await isInConfigMode() else { return "" }

        var output = try await sendCommand(
            exitConfig,
            expectString: "(?:Cannot exit: configuration modified|#)",
            stripPrompt: false,
            stripCommand: false
        )
        if output.contains("Cannot exit: configuration modified") {
            output += try await sendCommand(
                "exit discard",
                expectString: "#",
                stripPrompt: false,
                stripCommand: false
            )
        }
        if try await isInConfigMode() {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }
        return output
    }

    // MARK: Prompt Detection

    override public func setBasePrompt(
        primaryTerminator: String = "$",
        altTerminator: String = "#",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        let resolvedPattern = pattern ?? {
            let pri = NSRegularExpression.escapedPattern(for: primaryTerminator)
            let alt = NSRegularExpression.escapedPattern(for: altTerminator)
            let gt = NSRegularExpression.escapedPattern(for: ">")
            return "(\(pri)|\(alt)|\(gt))"
        }()
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: resolvedPattern
        )
        // VyOS prompt: user@hostname — strip the two trailing characters
        basePrompt = String(basePrompt.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Config Set

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

    override public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        var output = try await enterConfigMode()
        output += try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
        output += try await exitConfigMode()
        guard output.contains("Done") else {
            throw SwiftmikoError.commandFailed("Save failed with following errors:\n\n\(output)")
        }
        return output
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    @discardableResult
    public func commit(
        comment: String = "",
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        let errorMarkers = ["Failed to generate committed config", "Commit failed"]
        var commandString = "commit"
        if !comment.isEmpty {
            commandString += " comment \"\(comment)\""
        }

        var output = try await enterConfigMode()
        output += try await sendCommand(commandString, readTimeout: readTimeout, stripPrompt: false, stripCommand: false)

        if errorMarkers.contains(where: output.contains) {
            throw SwiftmikoError.commandFailed("Commit failed with following errors:\n\n\(output)")
        }
        return output
    }
}
