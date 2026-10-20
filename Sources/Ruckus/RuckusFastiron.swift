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
// Sources/Swiftmiko/Ruckus/RuckusFastiron.swift

import Foundation

/// Ruckus FastIron (ICX) base driver.
///
/// FastIron requires enable mode before disabling paging.
/// The enable flow supports RADIUS-style prompts for User Name or Login
/// in addition to the standard password prompt.
///
/// Maps to netmiko's RuckusFastironBase(CiscoSSHConnection).
open class RuckusFastironBase: CiscoSSHConnection {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "skip-page-display")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Enter enable mode.
    ///
    /// Supports RADIUS authentication which can prompt for User Name or Login
    /// in addition to the standard password prompt.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "(?:ssword|User Name|Login|No password has been assigned)",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        if checkState, try await isInEnableMode() {
            return ""
        }

        var output = ""
        for _ in 1..<4 {
            try await writeChannel(command + profile.returnCharacter)
            var newData = try await readUntilPromptOrPattern(
                pattern: pattern,
                caseInsensitive: caseInsensitive
            )
            output += newData

            if newData.contains("User Name") || newData.contains("Login") {
                try await writeChannel(profile.username + profile.returnCharacter)
                newData = try await readUntilPromptOrPattern(
                    pattern: pattern,
                    caseInsensitive: caseInsensitive
                )
                output += newData
            }

            if newData.lowercased().contains("ssword") {
                try await writeChannel(secret + profile.returnCharacter)
                newData = try await readUntilPrompt()
                output += newData
                if newData.range(of: "error.*incorrect.*password", options: [.regularExpression, .caseInsensitive]) == nil {
                    break
                }
            }

            if newData.contains("No password has been assigned") {
                break
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        if try await !isInEnableMode() {
            throw SwiftmikoError.commandFailed(
                "Failed to enter enable mode. Please ensure you pass the 'secret' argument to ConnectHandler."
            )
        }
        return output
    }

    // MARK: Save Config

    override public func saveConfig(
        command: String = "write mem",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

/// Ruckus FastIron SSH driver.
///
/// Maps to netmiko's RuckusFastironSSH(RuckusFastironBase).
public final class RuckusFastironSSH: RuckusFastironBase {}

/// Ruckus FastIron Telnet driver.
///
/// Maps to netmiko's RuckusFastironTelnet(RuckusFastironBase).
///
/// Ruckus FastIron/ICX does not always echo commands to output by
/// default over Telnet — if the server expresses interest in the
/// ECHO option (in either direction), this requests the SERVER do
/// local echo ("DO ECHO"), regardless of which negotiation verb
/// triggered it. Every other option is refused, same general
/// "don't negotiate anything else" policy as IP Infusion OcNOS's
/// equivalent, just with ECHO specifically carved out first.
public final class RuckusFastironTelnet: RuckusFastironBase {

    /// Maps to netmiko's __init__ override.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r\n"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    /// Handle a single IAC negotiation event from the telnet stream.
    ///
    /// Maps to netmiko's _process_option(tsocket, command, option).
    private func processTelnetOption(
        command: UInt8,
        option: UInt8
    ) async throws {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            return
        }

        if option == TelnetOption.ECHO {
            try await telnetChannel.sendRawOption(command: TelnetOption.DO, option: TelnetOption.ECHO)
        } else if command == TelnetOption.DO || command == TelnetOption.DONT {
            try await telnetChannel.sendRawOption(command: TelnetOption.WONT, option: option)
        } else if command == TelnetOption.WILL || command == TelnetOption.WONT {
            try await telnetChannel.sendRawOption(command: TelnetOption.DONT, option: option)
        }
    }

    /// Perform telnet login, installing the option negotiation
    /// callback first so it's active for the entire login sequence.
    ///
    /// Maps to netmiko's telnet_login().
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = #"(?m)#\s*$"#,
        altTerminator: String = #"(?m)>\s*$"#,
        usernamePattern: String = "(?:user:|username|login|user name)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            throw SwiftmikoError.connectionFailed(
                "RuckusFastironTelnet requires a channel conforming to " +
                "TelnetNegotiatingChannel to handle option negotiation"
            )
        }

        await telnetChannel.setOptionNegotiationCallback { [weak self] command, option in
            try await self?.processTelnetOption(command: command, option: option)
        }

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
