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

// Support for BinTec/Funkwerk (BOSS) devices
open class BintecBossBase: CiscoBaseConnection {

    // Prepare session and set base prompt
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
    }

    // Save Config to flash.
    @discardableResult
    override public func saveConfig(
        command: String = "cmd=save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // Reloads the device.
    @discardableResult
    public func reloadDevice(
        command: String = "cmd=reboot",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommandTiming(command)
    }
}

public final class BintecBossSSH: BintecBossBase {}

public final class BintecBossTelnet: BintecBossBase {}
