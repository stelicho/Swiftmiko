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
// Sources/Swiftmiko/Rad/RadETX.swift

import Foundation

/// RAD ETX base driver. Tested on RAD 203AX, 205A, and 220A.
///
/// Maps to netmiko's RadETXBase(BaseConnection).
open class RadETXBase: BaseConnection {

    // MARK: Session Preparation

    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await disablePaging(command: "config term length 0")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    /// RadETXBase extends BaseConnection directly, whose
    /// disablePaging() unconditionally throws — this gives it the same
    /// real generic behavior CiscoBaseConnection-rooted drivers get.
    /// sessionPreparation() always passes its own explicit command, so
    /// this override's own default is never actually relied upon.
    @discardableResult
    override public func disablePaging(
        command: String = "config term length 0",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await genericDisablePaging(command: command)
    }

    // MARK: Config Mode

    override public func isInConfigMode(
        checkString: String = ">config",
        pattern: String = ""
    ) async throws -> Bool {
        return try await genericIsInConfigMode(checkString: checkString, pattern: pattern)
    }

    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = ">config",
        dotAll: Bool = false
    ) async throws -> String {
        return try await genericEnterConfigMode(command: command, pattern: pattern, dotAll: dotAll)
    }

    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit all",
        pattern: String = "#"
    ) async throws -> String {
        return try await genericExitConfigMode(exitConfig: exitConfig, pattern: pattern)
    }

}

/// RAD ETX SSH driver.
///
/// Maps to netmiko's RadETXSSH(RadETXBase).
public final class RadETXSSH: RadETXBase {}

/// RAD ETX Telnet driver.
///
/// Maps to netmiko's RadETXTelnet(RadETXBase).
/// RAD presents with "user>" / "password>" prompts on login.
public final class RadETXTelnet: RadETXBase {

    override public func telnetLogin(
        primaryTerminator: String = "#\\s*$",
        altTerminator: String = "#\\s*$",
        usernamePattern: String = "(?:user>)",
        passwordPattern: String = "assword",
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
