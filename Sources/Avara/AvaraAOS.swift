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

// Avara AOS SSH Driver for Netmiko.
open class AvaraAosSSH: CiscoSSHConnection {

    // Example prompts:
    //   User:   `DEVNAME % `
    //   Config: `DEVNAME* % `
    // Maps to netmiko's prompt_pattern = r"\w\s%". The inherited
    // CiscoBaseConnection default ("[>#]") never matches this
    // device's real "%"-terminated prompt, which would otherwise hang
    // every connection during session preparation.
    override public nonisolated var promptPattern: String { #"\w\s%"# }

    /// Maps to netmiko's session_preparation():
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.base_prompt = self.find_prompt()
    ///
    /// Deliberately simpler than the generic Cisco flow — real
    /// Netmiko doesn't disable paging or run setBasePrompt's
    /// terminator-validation logic for this platform, just a raw
    /// prompt capture.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: promptPattern)
        basePrompt = try await findPrompt()
    }

    // Enable mode and config mode on Avara are the same.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "assword",
        enablePattern: String? = nil,
        checkState: Bool = false,
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

    // Enable mode and config mode on Avara are the same.
    @discardableResult
    override public func enterConfigMode(
        command: String = "enable",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await enterEnableMode(secret: profile.secret ?? "", command: command)
    }

    // Enable mode and config mode on Avara are the same.
    @discardableResult
    override public func exitEnableMode(exitCommand: String = "disable") async throws -> String {
        return try await exitConfigMode(exitConfig: exitCommand)
    }

    // Enable mode and config mode on Avara are the same.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "disable",
        pattern: String = #"Edit mode exited\."#
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig, pattern: pattern)
    }

    // Enable mode and config mode on Avara are the same.
    override public func isInEnableMode(checkString: String = "* %") async throws -> Bool {
        return try await isInConfigMode(checkString: checkString)
    }

    // Enable mode and config mode on Avara are the same.
    override public func isInConfigMode(
        checkString: String = "* %",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)
        let output = try await readChannelTiming(readTimeout: 0.5)
        return output.contains(checkString)
    }

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
        terminator: String = "%",
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

    // Apply pending edits then save configuration to flash.
    @discardableResult
    override public func saveConfig(
        command: String = "save flash",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        _ = try await sendCommand("apply", expectString: "Edits applied.")
        return try await super.saveConfig(command: command, confirm: confirm, confirmResponse: confirmResponse)
    }
}
