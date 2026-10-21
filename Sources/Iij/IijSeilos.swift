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
// Sources/Swiftmiko/Iij/IijSeilos.swift

import Foundation

/// Common methods for IIJ SEIL OS devices.
///
/// Maps to netmiko's IIJSeilosBase(NoEnable, NoConfig, BaseConnection).
///
/// Currently tested on SEIL/x86 Ayame, per Netmiko's own module
/// docstring. No privilege escalation and no configuration mode via
/// this connection type — hence NoEnable + NoConfig.
open class IIJSeilosBase: BaseConnection, NoEnable, NoConfig {

    // NoConfig: real Netmiko's mixin is a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->""),
    // not a throw — see Sources/NoConfig.swift for why this needs a
    // direct override rather than a protocol extension default.
    override public func isInConfigMode(checkString: String = "", pattern: String = "") async throws -> Bool {
        NoConfigBehavior.isInConfigMode()
    }

    @discardableResult
    override public func enterConfigMode(command: String = "", pattern: String = "", dotAll: Bool = false) async throws -> String {
        NoConfigBehavior.enter()
    }

    @discardableResult
    override public func exitConfigMode(exitConfig: String = "exit", pattern: String = "") async throws -> String {
        NoConfigBehavior.exit()
    }

    // NoEnable: same trivial-pass-through story — see Sources/NoEnable.swift.
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

    /// IIJSeilosBase extends BaseConnection directly, whose
    /// disablePaging() unconditionally throws — this gives it the same
    /// real generic behavior CiscoBaseConnection-rooted drivers get.
    /// sessionPreparation() always passes its own explicit command, so
    /// this override's own default is never actually relied upon.
    @discardableResult
    override public func disablePaging(
        command: String = "environment pager off",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await genericDisablePaging(command: command)
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "#")
        try await setBasePrompt()
        try await disablePaging(command: "environment pager off")
        try await setTerminalWidth(command: "environment terminal column 511")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: ANSI Handling

    /// Strip ANSI escape codes, including DEC private mode sequences
    /// beyond what the base stripper handles.
    ///
    /// Maps to netmiko's strip_ansi_escape_codes() override.
    ///
    /// Two additional sequence families are stripped here:
    ///   - DEC private mode set (ESC[?<n>h), e.g. ESC[?1h for cursor
    ///     key mode — a terminal-mode toggle, not visible content.
    ///   - DECKPAM/DECKPNM (ESC= and ESC>) — keypad application/
    ///     numeric mode switches, similarly invisible terminal state
    ///     rather than actual command output.
    override public func stripAnsiEscapeCodes(_ input: String) -> String {
        var output = super.stripAnsiEscapeCodes(input)
        output = output.replacingOccurrences(
            of: #"\x1b\[\?\d+h"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: "\u{1B}[=>]",
            with: "",
            options: .regularExpression
        )
        return output
    }

    // MARK: Save Config

    /// Save the running configuration to flash memory.
    ///
    /// Maps to netmiko's save_config(cmd="save-to flashrom").
    ///
    /// Sends the command directly rather than through the base
    /// saveConfig machinery — same bypass pattern as Juniper
    /// ScreenOS and Fujitsu Si-R, since this command needs no
    /// confirm/confirmResponse handling.
    public func saveConfig(
        command: String = "save-to flashrom",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(command)
    }
}

// MARK: - IIJSeilosSSH

/// IIJ SEIL OS SSH driver — no differences from the base.
/// Maps to netmiko's IIJSeilosSSH(IIJSeilosBase).
public final class IIJSeilosSSH: IIJSeilosBase {}

// MARK: - IIJSeilosTelnet

/// IIJ SEIL OS Telnet driver.
///
/// Maps to netmiko's IIJSeilosTelnet(IIJSeilosBase). Overrides the
/// default line ending to a bare "\n" — the same choice YamahaTelnet
/// made — unless the caller's profile already specifies one.
public final class IIJSeilosTelnet: IIJSeilosBase {

    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\n"
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
