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

/// Digi TransPort routers do not expose Cisco enable or configuration modes.
open class DigiTransportBase: CiscoBaseConnection, NoEnable, NoConfig {
    public init(
        profile: ConnectionProfile,
        defaultEnter: String? = nil,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var profile = profile
        profile.returnCharacter = defaultEnter ?? "\r\n"

        super.init(
            profile: profile,
            sessionLog: sessionLog,
            logLabel: "swiftmiko.digi_transport",
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

    // NoConfig: real Netmiko's mixin is likewise a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->""), not
    // a throw — real DigiTransportBase has no custom send_config_set
    // override either, so sendConfigSet() here just falls through to
    // BaseConnection's generic implementation once these three return
    // the no-op values instead of throwing.
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
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        NoConfigBehavior.exit()
    }

    @discardableResult
    override public func saveConfig(
        command: String = "config 0 save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        _ = confirm
        _ = confirmResponse

        return try await sendCommand(
            command,
            expectString: "Please wait...",
            stripPrompt: false,
            stripCommand: false
        )
    }
}

public final class DigiTransportSSH: DigiTransportBase {}
