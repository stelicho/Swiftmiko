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
// Sources/Swiftmiko/Ruijie/RuijieOS.swift

import Foundation

/// Ruijie RGOS base driver.
///
/// Maps to netmiko's RuijieOSBase(CiscoBaseConnection).
open class RuijieOSBase: CiscoBaseConnection {

    private static let promptPattern = "[>#]"

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        let pwdChangeMsg = "Do you want to change the password"
        let initPattern = "(?:\(pwdChangeMsg)|\(RuijieOSBase.promptPattern))"

        let data = try await readUntilPattern(pattern: initPattern)
        if data.contains(pwdChangeMsg) {
            _ = try await sendCommand("n", expectString: RuijieOSBase.promptPattern)
        }

        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await setTerminalWidth(command: "terminal width 256", pattern: "terminal")
        try await disablePaging(command: "terminal length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Save Config

    override public func saveConfig(
        command: String = "write",
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

/// Ruijie RGOS SSH driver.
///
/// Maps to netmiko's RuijieOSSSH(RuijieOSBase).
public final class RuijieOSSSH: RuijieOSBase {}

/// Ruijie RGOS Telnet driver.
///
/// Maps to netmiko's RuijieOSTelnet(RuijieOSBase). Overrides the
/// default line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class RuijieOSTelnet: RuijieOSBase {

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
}
