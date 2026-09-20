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
// Sources/Swiftmiko/Nec/NecIx.swift

import Foundation

/// Common implementation for NEC IX router devices (both SSH and
/// Telnet).
///
/// Maps to netmiko's NecIxBase(BaseConnection).
///
/// The most complete "enable mode IS config mode" aliasing in this
/// vendor set — more thorough even than HP Comware's or Linux's
/// versions. Here, isInConfigMode(), enterConfigMode(), and
/// exitConfigMode() all forward directly to their enable-mode
/// equivalents with NO parameters of their own retained; there is
/// genuinely no distinction between the two concepts on this
/// platform at all.
open class NecIxBase: BaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Note the unusual paging command: `self.RETURN +
    /// "terminal length 0"` — a leading return character prepended
    /// to the command itself, same pattern as NetScaler's paging
    /// command, likely for the same reason (ensuring the command
    /// starts on a fresh line).
    override public func sessionPreparation() async throws {
        try await setBasePrompt()
        _ = try await enterConfigMode()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
        try await disablePaging(command: profile.returnCharacter + "terminal length 0")
        _ = try await exitConfigMode()
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="#",
    /// alt_prompt_terminator="").
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = "",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
    }

    // MARK: Enable Mode

    /// Enter enable mode, which on NEC IX is identical to entering
    /// configuration mode.
    ///
    /// Maps to netmiko's enable(cmd="svintr-config", ...).
    ///
    /// Netmiko's own comment documents three interchangeable
    /// commands that all reach the same place on this platform:
    /// "svintr-config" (supervisor interrupt), "enable-config", or
    /// "configure" — this driver uses the first as its default.
    /// After the base enable sequence completes, it ALWAYS additionally
    /// sends a bare "configure" command and waits for the ")#" prompt
    /// shape — ensuring the session lands at the TOP level of
    /// config/enable mode specifically, not some arbitrary sub-context
    /// the initial command might have left it in.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "svintr-config",
        pattern: String = "",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        var output = try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive
        )
        // Ensure we're at the top level of config/enable mode.
        output += try await sendCommand(
            "configure",
            expectString: #")#"#
        )
        return output
    }

    /// Maps to netmiko's check_enable_mode(check_string=")#").
    override public func isInEnableMode(
        checkString: String = ")#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Exit "svintr-config" mode.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="exit").
    ///
    /// Same top-level-navigation discipline as enterEnableMode()
    /// above — before sending the actual exit command, this first
    /// re-navigates to the top of config/enable mode, ensuring the
    /// exit command isn't sent from some nested sub-context where it
    /// might only pop one level rather than exiting entirely.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        // Ensure we're at the top level of config/enable mode.
        output += try await sendCommand(
            "configure",
            expectString: #")#"#
        )

        try await writeChannel(normalizeCommand(exitCommand))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        output += try await readChannel()

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable/config mode.")
        }
        return output
    }

    // MARK: Config Mode — Fully Aliased to Enable Mode

    /// Config mode and enable mode behave identically on this
    /// platform.
    /// Maps to netmiko's config_mode() — forwards directly to
    /// enterEnableMode() with no parameters retained at all.
    @discardableResult
    override public func enterConfigMode(
        command: String = "",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await enterEnableMode(secret: profile.secret ?? "")
    }

    /// Maps to netmiko's check_config_mode() — forwards directly to
    /// isInEnableMode().
    override public func isInConfigMode(
        checkString: String = "",
        pattern: String = ""
    ) async throws -> Bool {
        return try await isInEnableMode()
    }

    /// Maps to netmiko's exit_config_mode() — forwards directly to
    /// exitEnableMode().
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        return try await exitEnableMode()
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="write memory",
    /// read_timeout=100.0).
    ///
    /// Explicitly enters config mode first (which, per the aliasing
    /// above, is identical to entering enable mode) before running
    /// the save command directly rather than through the base
    /// saveConfig machinery.
    public func saveConfig(
        command: String = "write memory",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        _ = try await enterConfigMode()
        return try await sendCommand(
            command,
            readTimeout: 100.0,
            stripPrompt: false,
            stripCommand: false
        )
    }
}

// MARK: - NecIxSSH

/// NEC IX SSH driver — no differences from the base.
/// Maps to netmiko's NecIxSSH(NecIxBase).
public final class NecIxSSH: NecIxBase {}

// MARK: - NecIxTelnet

/// NEC IX Telnet driver.
///
/// Maps to netmiko's NecIxTelnet(NecIxBase).
///
/// Third driver in this vendor set needing raw Telnet IAC option
/// negotiation, after ZteZxrosTelnet and IpInfusionOcNOSTelnet — and
/// this one's negotiation policy is functionally IDENTICAL to ZTE's:
/// accept ECHO/SGA when offered, negotiate a fixed 500x50 window size
/// via NAWS, refuse everything else. Worth noting as a strong
/// candidate for a genuinely shared implementation once you're
/// writing real code, rather than three near-duplicate
/// processTelnetOption() methods across separate files.
public final class NecIxTelnet: NecIxBase {

    /// NEC IX requires a bare "\r" line ending.
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

    /// Handle a single IAC negotiation event from the telnet stream.
    ///
    /// Maps to netmiko's _process_option(telnet_sock, cmd, opt) —
    /// identical policy to ZteZxrosTelnet.processTelnetOption(): accept
    /// ECHO/SGA offers, negotiate a fixed 500x50 window via NAWS,
    /// refuse anything else.
    private func processTelnetOption(
        command: UInt8,
        option: UInt8
    ) async throws {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            return
        }

        switch command {
        case TelnetOption.WILL:
            if option == TelnetOption.ECHO || option == TelnetOption.SGA {
                try await telnetChannel.sendRawOption(command: TelnetOption.DO, option: option)
            } else {
                try await telnetChannel.sendRawOption(command: TelnetOption.DONT, option: option)
            }

        case TelnetOption.DO:
            if option == TelnetOption.NAWS {
                try await telnetChannel.sendRawOption(command: TelnetOption.WILL, option: option)
                // Width: 500, Height: 50
                let windowSize: [UInt8] = [0x01, 0xf4, 0x00, 0x32]
                try await telnetChannel.sendSubnegotiation(
                    option: TelnetOption.NAWS,
                    payload: windowSize
                )
            } else {
                try await telnetChannel.sendRawOption(command: TelnetOption.WONT, option: option)
            }

        default:
            break
        }
    }

    /// Perform telnet login, installing the option negotiation
    /// callback first so it's active for the entire login sequence.
    ///
    /// Maps to netmiko's telnet_login(pri_prompt_terminator=r"#\s*$",
    /// alt_prompt_terminator=r">\s*$", username_pattern=r"login",
    /// pwd_pattern=r"assword").
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = #"#\s*$"#,
        altTerminator: String = #">\s*$"#,
        usernamePattern: String = "login",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            throw SwiftmikoError.connectionFailed(
                "NecIxTelnet requires a channel conforming to " +
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
