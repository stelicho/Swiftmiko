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

// Brocade Fabric OS support.
//
// Maps to netmiko's BrocadeFOSSSH(NoEnable, NoConfig,
// CiscoSSHConnection) — this platform has neither an enable mode nor
// a traditional conf-t style config mode.
public final class BrocadeFOSSSH: CiscoSSHConnection, NoEnable, NoConfig {

    /// Brocade Fabric OS requires a bare "\r" line ending.
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
            adjustedProfile.returnCharacter = "\r"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // NoEnable: real Netmiko's mixin is a trivial pass-through
    // (check_enable_mode->True, enable/exit_enable_mode->"") — see
    // Sources/NoEnable.swift for why this needs a direct override
    // rather than a protocol extension default.
    override public func isInEnableMode(checkString: String = "") async throws -> Bool {
        NoEnableBehavior.isInEnableMode()
    }

    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "",
        pattern: String = "",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        NoEnableBehavior.enter()
    }

    @discardableResult
    override public func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        NoEnableBehavior.exit()
    }

    // NoConfig: real Netmiko's mixin is a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->"") —
    // see Sources/NoConfig.swift for why this needs a direct override
    // rather than a protocol extension default.
    override public func isInConfigMode(checkString: String = "", pattern: String = "") async throws -> Bool {
        NoConfigBehavior.isInConfigMode()
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        NoConfigBehavior.enter()
    }

    @discardableResult
    override public func exitConfigMode(exitConfig: String = "exit", pattern: String = "") async throws -> String {
        NoConfigBehavior.exit()
    }

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
    }
}
