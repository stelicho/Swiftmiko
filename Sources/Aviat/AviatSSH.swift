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
import Foundation

// Aviat WTM Outdoor Radio support.
open class AviatWTMSSH: CiscoSSHConnection {

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
    }

    @discardableResult
    override public func disablePaging(
        command: String = "session paginate false",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await sendConfigSet([command])
    }

    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.findPrompt(delay: delay, pattern: pattern ?? #"[$>#]"#)
    }

    // Exit configuration mode.
    // Raises error if uncommitted changes are detected — call commit() first.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = #"(?:Uncommitted changes|#)"#
    ) async throws -> String {
        var output = ""
        guard try await isInConfigMode() else { return output }

        try await writeChannel(normalizeCommand(exitConfig))
        if cmdVerifyEnabled {
            _ = try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(
                    for: exitConfig.trimmingCharacters(in: .whitespaces)
                )
            )
        }
        output += try await readUntilPattern(pattern: pattern)
        if output.contains("Uncommitted changes") {
            throw SwiftmikoError.commandFailed(
                "Uncommitted changes detected — call commit() before exiting config mode."
            )
        }
        if try await isInConfigMode() {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode.")
        }
        return output
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(command: command, pattern: pattern)
    }

    // Send config commands; defaults to not exiting config mode (call commit() explicitly).
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

    // Commit configuration changes on Aviat WTM devices.
    func commit(command: String = "commit", readTimeout: TimeInterval = 120.0) async throws -> String {
        guard try await isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Must be in configuration mode to commit.")
        }
        try await writeChannel(normalizeCommand(command))
        let output = try await readUntilPattern(pattern: #"\)#"#, timeout: readTimeout)
        return output
    }

    // Aviat WTM Outdoor Radio does not have a 'save config' command.
    @discardableResult
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented("AviatWTM does not support saveConfig()")
    }
}
