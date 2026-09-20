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

    override public nonisolated var supportsConfigMode: Bool {
        false
    }

    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        _ = secret
        return ""
    }

    override public func isInEnableMode(checkString: String = "#") async throws -> Bool {
        true
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        throw SwiftmikoError.configModeNotSupported
    }

    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return ""
    }

    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
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
        _ = commands
        _ = exitConfigMode
        throw SwiftmikoError.configModeNotSupported
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
