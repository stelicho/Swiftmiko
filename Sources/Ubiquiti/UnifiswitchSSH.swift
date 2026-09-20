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
// Sources/Swiftmiko/Ubiquiti/UnifiswitchSSH.swift

import Foundation

/// Ubiquiti UniFi Switch SSH driver.
///
/// When SSHing to a UniFi switch, the session initially starts at a
/// Linux shell. Running `telnet localhost` drops into the familiar
/// EdgeSwitch-style environment.
///
/// Maps to netmiko's UbiquitiUnifiSwitchSSH(UbiquitiEdgeSSH).
public final class UbiquitiUnifiSwitchSSH: UbiquitiEdgeSSH {

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        _ = try await sendCommand(
            "telnet localhost",
            expectString: #"\(UBNT\) >"#
        )
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    override public func cleanup(command: String = "exit") async throws {
        if try await isInConfigMode() {
            _ = try? await exitConfigMode()
        }
        // Exit from the telnet localhost session
        try await writeChannel(command + profile.returnCharacter)
        try await super.cleanup(command: command)
    }
}
