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
// Sources/Swiftmiko/Zte/ZteZxros.swift

import Foundation

// MARK: - ZteZxrosBase

/// Common implementation for ZTE ZXROS devices (both SSH and Telnet).
///
/// Maps to netmiko's ZteZxrosBase(CiscoBaseConnection).
open class ZteZxrosBase: CiscoBaseConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging()
        // Settle delay before draining the buffer — matches Netmiko's
        // fixed 0.3s wait (global_delay_factor is not yet modeled here).
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#", pattern="#")
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "#"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// ZTE uses a bare "write" command rather than "write mem" or
    /// "copy running-config startup-config".
    /// Maps to netmiko's save_config(cmd="write").
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

// MARK: - ZteZxrosSSH

/// ZTE ZXROS SSH driver — no differences from the base.
/// Maps to netmiko's ZteZxrosSSH(ZteZxrosBase).
public final class ZteZxrosSSH: ZteZxrosBase {}

// MARK: - ZteZxrosTelnet

/// ZTE ZXROS Telnet driver.
///
/// Maps to netmiko's ZteZxrosTelnet(ZteZxrosBase).
///
/// ZTE's telnet server does not properly auto-negotiate terminal
/// options. Without an explicit reply to WILL/DO requests, the
/// session can hang or render garbled output. This driver installs
/// a negotiation callback that:
///   - Agrees to ECHO and SGA (suppress go-ahead) when the server
///     offers them (WILL)
///   - Refuses any other WILL offer
///   - Answers a NAWS (window size) request from the server by
///     advertising a fixed 500x50 terminal window
///   - Refuses any other DO request
public final class ZteZxrosTelnet: ZteZxrosBase {

    /// Handles a single IAC negotiation event from the telnet stream.
    ///
    /// Maps to netmiko's static _process_option(telnet_sock, cmd, opt),
    /// with `telnet_sock.sendall(...)` replaced by writing the raw
    /// bytes back through the channel.
    ///
    /// This can only run once `channel` is a TelnetChannel exposing a
    /// raw byte-write primitive — see the TelnetChannel protocol
    /// extension below.
    private func processTelnetOption(
        command: UInt8,
        option: UInt8
    ) async throws {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            // Non-telnet channel (e.g. a test double) — nothing to do.
            return
        }

        switch command {
        case TelnetOption.WILL:
            if option == TelnetOption.ECHO || option == TelnetOption.SGA {
                // Reply: DO <option> — accept the server's offer
                try await telnetChannel.sendRawOption(
                    command: TelnetOption.DO,
                    option: option
                )
            } else {
                // Reply: DONT <option> — refuse anything else
                try await telnetChannel.sendRawOption(
                    command: TelnetOption.DONT,
                    option: option
                )
            }

        case TelnetOption.DO:
            if option == TelnetOption.NAWS {
                // Reply: WILL NAWS, then subnegotiate a fixed window size
                try await telnetChannel.sendRawOption(
                    command: TelnetOption.WILL,
                    option: option
                )
                // Width: 500, Height: 50 — matches Netmiko's
                // b"\x01\xf4\x00\x32" (500 and 50 as big-endian UInt16s)
                let windowSize: [UInt8] = [0x01, 0xf4, 0x00, 0x32]
                try await telnetChannel.sendSubnegotiation(
                    option: TelnetOption.NAWS,
                    payload: windowSize
                )
            } else {
                // Reply: WONT <option> — refuse anything else
                try await telnetChannel.sendRawOption(
                    command: TelnetOption.WONT,
                    option: option
                )
            }

        default:
            // SB, SE, and anything else pass through untouched —
            // Netmiko's callback only handles WILL and DO.
            break
        }
    }

    /// Perform telnet login, installing the option negotiation callback
    /// first so it's active for the entire login sequence.
    ///
    /// Maps to netmiko's telnet_login(), which asserts self.remote_conn
    /// is a Telnet instance and registers _process_option before
    /// delegating to the base implementation.
    override public func telnetLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(?:username|login)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            throw SwiftmikoError.connectionFailed(
                "ZteZxrosTelnet requires a channel conforming to " +
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
