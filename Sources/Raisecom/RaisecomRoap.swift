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
// Sources/Swiftmiko/Raisecom/RaisecomRoap.swift

import Foundation

/// Raisecom ROAP base driver.
///
/// Maps to netmiko's RaisecomRoapBase(CiscoBaseConnection).
open class RaisecomRoapBase: CiscoBaseConnection {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "terminal page-break disable")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Config Mode

    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(checkString: checkString, pattern: pattern)
    }

    // MARK: Save Config

    override public func saveConfig(
        command: String = "write startup-config",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        _ = try? await exitConfigMode()
        try await enterEnableMode(secret: profile.secret ?? "")
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}

/// Raisecom ROAP SSH driver.
///
/// Some OS versions present with "Login:" / "Password:" prompts
/// rather than using the standard SSH exchange.
///
/// Maps to netmiko's RaisecomRoapSSH(RaisecomRoapBase).
public final class RaisecomRoapSSH: RaisecomRoapBase {

    /// Walk the special Login:/Password: handshake seen on certain OS versions.
    public func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let activeDelay = selectDelayFactor(delay)
        try await Task.sleep(nanoseconds: UInt64(activeDelay * 0.5 * 1_000_000_000))

        for _ in 0..<13 {
            let output = try await readChannel()
            if !output.isEmpty {
                if output.contains("Login:") {
                    try await writeChannel(profile.username + profile.returnCharacter)
                } else if output.contains("Password:") {
                    try await writeChannel((profile.passwordString ?? "") + profile.returnCharacter)
                    break
                }
                try await Task.sleep(nanoseconds: UInt64(activeDelay * 1.0 * 1_000_000_000))
            } else {
                try await writeChannel(profile.returnCharacter)
                try await Task.sleep(nanoseconds: UInt64(activeDelay * 1.5 * 1_000_000_000))
            }
        }
    }
}

/// Raisecom ROAP Telnet driver.
///
/// Maps to netmiko's RaisecomRoapTelnet(RaisecomRoapBase).
public final class RaisecomRoapTelnet: RaisecomRoapBase {

    override public func telnetLogin(
        primaryTerminator: String = "#\\s*$",
        altTerminator: String = ">\\s*$",
        usernamePattern: String = "(Login|Username)",
        passwordPattern: String = "Password",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
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
