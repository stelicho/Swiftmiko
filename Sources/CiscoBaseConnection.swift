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
//  CiscoBaseConnection.swift
//  Swiftmiko
//
//  Port of netmiko/cisco/cisco_base_connection.py
//
//  REWORKED: renamed every method to match BaseConnection's actual
//  signatures so `override` resolves. Deleted duplicate private
//  helpers that already exist on BaseConnection (stripEcho→stripCommand,
//  stripTrailingPrompt→stripPrompt, normalizeCommand, clearBuffer,
//  normalizeLinefeeds). Class, not actor — actors can't be subclassed.
//

import Foundation

open class CiscoBaseConnection: BaseConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: - Enable mode

    override open func isInEnableMode(checkString: String = "#") async throws -> Bool {
        let prompt = try await findPrompt()
        return prompt.contains(checkString)
    }

    @discardableResult
    override open func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        if checkState, try await isInEnableMode() { return "" }

        try await writeChannel(command + profile.returnCharacter)
        var output = try await readUntilPromptOrPattern(pattern: pattern, timeout: profile.readTimeout)

        let sawPasswordPrompt = output.range(
            of: pattern, options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil

        if sawPasswordPrompt {
            guard let secretToSend = secret.isEmpty ? profile.secret : secret, !secretToSend.isEmpty else {
                throw SwiftmikoError.authenticationFailed(
                    "Enable password required for \(profile.host), but no secret was provided"
                )
            }
            try await writeChannel(secretToSend + profile.returnCharacter)
            output += try await readUntilPromptOrPattern(
                pattern: enablePattern ?? promptPattern, timeout: profile.readTimeout
            )
        }

        if let enablePattern, output.range(of: enablePattern, options: .regularExpression) == nil {
            throw SwiftmikoError.unexpectedPrompt("Did not reach enable mode on \(profile.host)")
        }
        return output
    }

    @discardableResult
    override open func exitEnableMode(exitCommand: String = "disable") async throws -> String {
        try await sendCommand(exitCommand, stripPrompt: false, stripCommand: false)
    }

    // MARK: - Configuration mode

    @discardableResult
    override open func enterConfigMode(
        command: String = "configure terminal",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        try await writeChannel(command + profile.returnCharacter)
        inConfigMode = true
        if pattern.isEmpty {
            return try await readUntilPrompt(timeout: profile.readTimeout)
        }
        return try await readUntilPromptOrPattern(pattern: pattern, timeout: profile.readTimeout)
    }

    @discardableResult
    override open func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = #"#.*"#
    ) async throws -> String {
        guard try await isInConfigMode() else { return "" }
        try await writeChannel(exitConfig + profile.returnCharacter)
        let output = pattern.isEmpty
            ? try await readUntilPrompt(timeout: profile.readTimeout)
            : try await readUntilPromptOrPattern(pattern: pattern, timeout: profile.readTimeout)
        inConfigMode = false
        return output
    }

    override open func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        let prompt = try await findPrompt()
        return !checkString.isEmpty && prompt.contains(checkString)
    }

    override open func isInConfigModeRegex(
        checkString: String,
        pattern: String = ""
    ) async throws -> Bool {
        let prompt = try await findPrompt()
        return prompt.range(of: checkString, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Telnet and serial login

    @discardableResult
    override open func serialLogin(
        primaryTerminator: String = #"\#\s*$"#,
        altTerminator: String = #">\s*$"#,
        usernamePattern: String = #"(?:user:|username|login)"#,
        passwordPattern: String = #"assword"#,
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        try await writeChannel("\r")
        let output = try await readChannel()
        if output.range(of: primaryTerminator, options: [.regularExpression, .caseInsensitive]) != nil ||
           output.range(of: altTerminator, options: [.regularExpression, .caseInsensitive]) != nil {
            return output
        }
        return try await telnetLogin(
            primaryTerminator: primaryTerminator, altTerminator: altTerminator,
            usernamePattern: usernamePattern, passwordPattern: passwordPattern,
            delay: delay, maxLoops: maxLoops
        )
    }

    // Cisco's telnetLogin behavior (3 outer retries) is close enough to
    // BaseConnection's default that it isn't overridden here — remove
    // this comment once confirmed BaseConnection's version is sufficient.

    // MARK: - Filesystem autodetection

    override open func autodetectFileSystem(
        command: String = "dir",
        pattern: String = #"Directory of (.*)/"#
    ) async throws -> String {
        guard try await isInEnableMode() else {
            throw SwiftmikoError.connectionFailed("Must be in enable mode to auto-detect the filesystem")
        }
        let output = try await sendCommand(command, stripPrompt: false, stripCommand: false)
        guard let fileSystem = firstCapture(pattern: pattern, in: output) else {
            throw SwiftmikoError.connectionFailed("Could not determine the remote filesystem from: \(output)")
        }
        let testOutput = try await sendCommand("dir \(fileSystem)", stripPrompt: false, stripCommand: false)
        if testOutput.contains("% Invalid") || testOutput.contains("%Error:") {
            throw SwiftmikoError.connectionFailed("Error determining remote filesystem: \(testOutput)")
        }
        return fileSystem
    }

    // MARK: - Save configuration

    @discardableResult
    open func saveConfig(
        command: String = "copy running-config startup-config",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        try await enterEnableMode(secret: profile.secret ?? "")
        if !confirm {
            return try await sendCommand(command, readTimeout: 100.0, stripPrompt: false, stripCommand: false)
        }
        try await writeChannel(command + profile.returnCharacter)
        var output = try await readUntilPromptOrPattern(pattern: #"\[[^\]]+\]|[>#]"#, timeout: 100.0)
        try await writeChannel((confirmResponse.isEmpty ? "" : confirmResponse) + profile.returnCharacter)
        output += try await readUntilPrompt(timeout: 100.0)
        return output
    }

    // MARK: - Paging / terminal width

    @discardableResult
    override open func disablePaging(
        command: String = "terminal length 0",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await sendCommand(command, stripPrompt: false, stripCommand: false)
    }

    open func setTerminalWidth(command: String, pattern: String) async throws {
        _ = try await sendCommand(command, expectString: pattern, stripPrompt: false, stripCommand: false)
    }

    // MARK: - Command send with an explicit expect pattern (Cisco-only convenience, NOT an override)

    @discardableResult
    open func sendCommand(
        _ command: String,
        expectString: String,
        readTimeout: TimeInterval? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true
    ) async throws -> String {
        try await writeChannel(command + profile.returnCharacter)
        var output = try await readUntilPromptOrPattern(pattern: expectString, timeout: readTimeout)
        if stripCommand { output = self.stripCommand(command, output: output) }
        if stripPrompt { output = self.stripPrompt(output) }
        return output
    }

    // MARK: - Private helpers

    private func firstCapture(pattern: String, in value: String) -> String? {
        guard let expr = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expr.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[captureRange])
    }
}

open class CiscoSSHConnection: CiscoBaseConnection {}
open class CiscoFileTransfer: BaseFileTransfer {}
