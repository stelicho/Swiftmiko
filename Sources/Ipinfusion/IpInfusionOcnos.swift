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
// Sources/Swiftmiko/IpInfusion/IpInfusionOcnos.swift

import Foundation

/// Common implementation for IP Infusion OcNOS devices (both SSH and
/// Telnet).
///
/// Maps to netmiko's IpInfusionOcNOSBase(CiscoBaseConnection).
///
/// OcNOS uses a full transactional configuration model: commit,
/// confirm-commit, cancel-commit, and abort-transaction are four
/// distinct operations, richer than any other commit-based driver in
/// this vendor set — most only offer commit with an optional
/// confirm/comment, but OcNOS treats a "commit confirmed" as
/// genuinely provisional until a SEPARATE confirm-commit call makes
/// it permanent, with cancel-commit as the explicit undo for that
/// provisional state.
open class IpInfusionOcNOSBase: CiscoBaseConnection {

    /// OcNOS requires a bare "\r" line ending.
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

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// The "terminal no monitor" step is worth calling out — Netmiko's
    /// own comment explains this turns off session-level logging that
    /// could otherwise interleave with and pollute command output,
    /// making it harder to parse cleanly. This is distinct from
    /// disabling PAGING; it's disabling a logging/monitoring feature
    /// entirely.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await disablePaging(command: "terminal length 0")
        // Turn off session logging — it can interleave with and
        // spoil analysis of command output.
        _ = try await sendCommand("terminal no monitor")
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Config Set

    /// Send a set of configuration commands, requiring a separate
    /// commit() call to actually apply them.
    ///
    /// Maps to netmiko's send_config_set() — defaults exitConfigMode
    /// to false unless the caller explicitly overrides it, same
    /// requirement as several other transactional/commit-based
    /// drivers in this vendor set (Cisco XR, CDOT CROS, Ericsson
    /// IPOS, Huawei VRPv8).
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = false,
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
        return try await super.sendConfigSet(commands, exitConfigMode: exitConfigMode)
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(confirm=false, confirm_delay=None,
    /// comment="", read_timeout=120.0).
    ///
    /// Command string construction:
    ///   default              → "commit"
    ///   confirm + delay      → "commit confirmed timeout <delay>"
    ///   confirm, no delay    → "commit confirmed"
    ///   comment              → appends " description <comment>"
    ///     (note: OcNOS's own terminology maps "comment" to the
    ///     device-side "description" keyword — worth remembering
    ///     when reading device output, since the caller-facing
    ///     parameter name and the actual command keyword differ)
    @discardableResult
    public func commit(
        confirm: Bool = false,
        confirmDelay: Int? = nil,
        comment: String = "",
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        guard !(confirmDelay != nil && !confirm) else {
            throw SwiftmikoError.invalidArgument(
                "Invalid arguments supplied to commit: confirmDelay specified without confirm"
            )
        }

        let errorMarker = "Failed to commit"
        var commandString = "commit"

        if confirm {
            commandString += " confirmed"
            if let confirmDelay {
                commandString += " timeout \(confirmDelay)"
            }
        }
        if !comment.isEmpty {
            commandString += " description \(comment)"
        }

        var output = try await enterConfigMode()
        output += try await sendCommand(
            commandString,
            readTimeout: readTimeout,
            expectString: "#",
            stripPrompt: false,
            stripCommand: false
        )

        guard !output.contains(errorMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }
        return output
    }

    /// Confirm a commit that was previously issued as "commit
    /// confirmed", making it permanent.
    ///
    /// Maps to netmiko's _confirm_commit(read_timeout=120.0).
    ///
    /// A successful confirm produces no distinctive output at all —
    /// the ABSENCE of "Error" in the response is the success signal,
    /// not the presence of any positive marker. Internal, not
    /// private, matching Netmiko's leading-underscore convention.
    @discardableResult
    internal func confirmCommit(readTimeout: TimeInterval = 120.0) async throws -> String {
        var output = try await enterConfigMode()

        let newData = try await sendCommand(
            "confirm-commit",
            readTimeout: readTimeout,
            expectString: "(#|Error)",
            stripPrompt: false,
            stripCommand: false
        )
        output += newData

        guard !newData.contains("Error") else {
            throw SwiftmikoError.commandFailed(
                "Confirm commit operation failed with the following errors:\n\n\(output)"
            )
        }
        return output
    }

    /// Cancel an ongoing confirmed commit before it's been confirmed.
    ///
    /// Maps to netmiko's _cancel_commit(read_timeout=120.0). Same
    /// silent-success-on-absence-of-error shape as confirmCommit()
    /// above.
    @discardableResult
    internal func cancelCommit(readTimeout: TimeInterval = 120.0) async throws -> String {
        var output = try await enterConfigMode()

        let newData = try await sendCommand(
            "cancel-commit",
            readTimeout: readTimeout,
            expectString: "(#|Error)",
            stripPrompt: false,
            stripCommand: false
        )
        output += newData

        guard !newData.contains("Error") else {
            throw SwiftmikoError.commandFailed(
                "Cancel commit operation failed with the following errors:\n\n\(output)"
            )
        }
        return output
    }

    /// Abort the current transaction entirely, discarding all pending
    /// (uncommitted) changes.
    ///
    /// Maps to netmiko's _abort_transaction(read_timeout=120.0).
    ///
    /// Unlike every other method in this file, this does NOT
    /// auto-enter config mode — it explicitly requires the caller to
    /// already be there, throwing immediately otherwise. This is a
    /// meaningful asymmetry worth preserving faithfully: presumably
    /// "abort transaction" only makes sense to run from inside an
    /// active config-mode session that has actual pending changes to
    /// discard, whereas commit/confirm-commit/cancel-commit are
    /// designed to be safely callable from anywhere and just navigate
    /// there first.
    @discardableResult
    internal func abortTransaction(readTimeout: TimeInterval = 120.0) async throws -> String {
        guard try await isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Device is not in config mode")
        }

        return try await sendCommand(
            "abort transaction",
            readTimeout: readTimeout,
            expectString: "#",
            stripPrompt: false,
            stripCommand: false
        )
    }

    // MARK: Save Config

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

// MARK: - IpInfusionOcNOSSSH

/// IP Infusion OcNOS SSH driver — no differences from the base.
/// Maps to netmiko's IpInfusionOcNOSSSH(IpInfusionOcNOSBase).
public final class IpInfusionOcNOSSSH: IpInfusionOcNOSBase {}

// MARK: - IpInfusionOcNOSTelnet

/// IP Infusion OcNOS Telnet driver.
///
/// Maps to netmiko's IpInfusionOcNOSTelnet(IpInfusionOcNOSBase).
///
/// Second driver in this vendor set needing raw Telnet IAC option
/// negotiation, after ZteZxrosTelnet — but a genuinely different
/// negotiation policy: rather than accepting specific options (ECHO,
/// SGA) and answering a NAWS window-size request, this REFUSES every
/// option outright, with exactly one exception — if the server asks
/// about terminal type (TTYPE), it proactively announces itself as
/// "xterm". This is a general "don't negotiate anything, but play
/// along on terminal type" policy, distinct from ZTE's
/// accept-specific-things policy.
public final class IpInfusionOcNOSTelnet: IpInfusionOcNOSBase {

    /// Handle a single IAC negotiation event from the telnet stream.
    ///
    /// Maps to netmiko's _process_option(tsocket, command, option).
    ///
    /// Policy:
    ///   DO + TTYPE  → announce WILL TTYPE, then subnegotiate the
    ///                 terminal type as "xterm"
    ///   DO / DONT   → reply WONT <option> (refuse to enable anything
    ///                 else the server is asking us to turn on)
    ///   WILL / WONT → reply DONT <option> (refuse to acknowledge
    ///                 anything else the server offers to enable on
    ///                 its own side)
    private func processTelnetOption(
        command: UInt8,
        option: UInt8
    ) async throws {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            return
        }

        switch command {
        case TelnetOption.DO where option == TelnetOption.TTYPE:
            try await telnetChannel.sendRawOption(command: TelnetOption.WILL, option: option)
            // Subnegotiate: IAC SB TTYPE 0 "xterm" IAC SE
            let xterm: [UInt8] = Array("xterm".utf8)
            try await telnetChannel.sendSubnegotiation(
                option: TelnetOption.TTYPE,
                payload: [0x00] + xterm
            )

        case TelnetOption.DO, TelnetOption.DONT:
            try await telnetChannel.sendRawOption(command: TelnetOption.WONT, option: option)

        case TelnetOption.WILL, TelnetOption.WONT:
            try await telnetChannel.sendRawOption(command: TelnetOption.DONT, option: option)

        default:
            break
        }
    }

    /// Perform telnet login, installing the option negotiation
    /// callback first so it's active for the entire login sequence.
    ///
    /// Maps to netmiko's telnet_login(pri_prompt_terminator="#",
    /// alt_prompt_terminator=">", username_pattern=r"(?:user:|
    /// sername|login|user name)", pwd_pattern=r"assword:").
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(?:user:|sername|login|user name)",
        passwordPattern: String = "assword:",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        guard let telnetChannel = channel as? TelnetNegotiatingChannel else {
            throw SwiftmikoError.connectionFailed(
                "IpInfusionOcNOSTelnet requires a channel conforming to " +
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
