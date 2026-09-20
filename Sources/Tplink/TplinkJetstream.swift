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
// Sources/Swiftmiko/Tplink/TplinkJetstream.swift

import Foundation

/// TP-Link JetStream base driver.
///
/// TP-Link doesn't support `terminal width` so `cmdVerify` must be
/// disabled. It also uses `\r\n` line endings.
///
/// Maps to netmiko's TPLinkJetStreamBase(CiscoSSHConnection).
open class TPLinkJetStreamBase: CiscoSSHConnection {

    // MARK: Init

    public required init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjusted = profile
        if adjusted.returnCharacter == "\n" {
            adjusted.returnCharacter = "\r\n"
        }
        super.init(
            profile: adjusted,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await setBasePrompt()
        try await disablePaging()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Enter enable mode.
    ///
    /// TP-Link JetStream requires running both "enable" and then
    /// "enable-admin" to reach full configuration access.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        if checkState, try await isInEnableMode() {
            return ""
        }

        // If a specific command was provided, use the standard path.
        if !command.isEmpty {
            return try await super.enterEnableMode(
                secret: secret,
                command: command,
                pattern: pattern,
                enablePattern: enablePattern,
                checkState: false,
                caseInsensitive: caseInsensitive
            )
        }

        var output = ""
        for cmd in ["enable", "enable-admin"] {
            try await writeChannel(cmd + profile.returnCharacter)
            let newData = try await readUntilPromptOrPattern(
                pattern: pattern,
                caseInsensitive: caseInsensitive
            )
            output += newData
            if newData.range(of: pattern, options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression) != nil {
                try await writeChannel(secret + profile.returnCharacter)
                output += try await readUntilPrompt()
            }
        }

        if try await !isInEnableMode() {
            throw SwiftmikoError.commandFailed(
                "Failed to enter enable mode. Please ensure you pass the 'secret' argument to ConnectHandler."
            )
        }
        return output
    }

    // MARK: Config Mode

    override public func isInConfigMode(
        checkString: String = "(config",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(checkString: checkString, pattern: pattern)
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(command: command, pattern: pattern, dotAll: dotAll)
    }

    /// TP-Link JetStream may have multiple nested config levels.
    /// Keep sending "exit" until fully out of config mode.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = "#"
    ) async throws -> String {
        var output = ""
        for _ in 0..<12 {
            guard try await isInConfigMode() else { break }
            try await writeChannel(exitConfig + profile.returnCharacter)
            output += try await readUntilPattern(pattern: pattern)
        }
        if try await isInConfigMode() {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }
        return output
    }

    // MARK: Prompt

    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = "#",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
    }
}

/// TP-Link JetStream SSH driver.
///
/// Note: devices that only offer a DSA host key are no longer supported
/// over SSH — use `tplink_jetstream_telnet` for those.
///
/// Maps to netmiko's TPLinkJetStreamSSH(TPLinkJetStreamBase).
public final class TPLinkJetStreamSSH: TPLinkJetStreamBase {}

/// TP-Link JetStream Telnet driver.
///
/// Maps to netmiko's TPLinkJetStreamTelnet(TPLinkJetStreamBase).
public final class TPLinkJetStreamTelnet: TPLinkJetStreamBase {

    override public func telnetLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "User:",
        passwordPattern: String = "Password:",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 60
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
