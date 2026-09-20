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
// Sources/Swiftmiko/Cisco/CiscoTpTcce.swift

import Foundation

/// Cisco Telepresence Endpoint (TC/CE software) SSH driver.
///
/// Also works for Cisco Expressway/VCS, which shares the same CLI
/// dialect.
///
/// Maps to netmiko's CiscoTpTcCeSSH(CiscoSSHConnection).
///
/// This is one of the strangest CLIs in the whole vendor set: there
/// is no real hostname-based prompt at all — every command's result
/// terminates in a bare "OK", "ERROR", or "Command not recognized."
/// line, and that literal string "OK" is used as the base prompt
/// throughout, rather than anything derived from the device itself.
public final class CiscoTpTcCeSSH: CiscoSSHConnection {

    /// TC/CE requires "\r\n" as the line ending.
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
            adjustedProfile.returnCharacter = "\r\n"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Paging

    /// Paging is disabled by default on this platform — hard no-op.
    /// Maps to netmiko's disable_paging().
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return ""
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Netmiko's own comment is worth preserving verbatim: the
    /// author "could not work out what the CLI looked like," hence
    /// testChannelRead() is called with no pattern at all — it just
    /// waits for any data rather than matching something specific.
    /// This is a candidate for improvement (matching a real pattern
    /// would be more reliable) but is carried over faithfully rather
    /// than guessing at a pattern that was never confirmed against
    /// real hardware.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Prompt Detection

    /// Always use "OK" as the base prompt, regardless of what the
    /// device would otherwise present.
    /// Maps to netmiko's set_base_prompt().
    override public func setBasePrompt(
        primaryTerminator: String = "",
        altTerminator: String = "",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        basePrompt = "OK"
    }

    /// Always return "OK" as the current prompt.
    /// Maps to netmiko's find_prompt().
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return "OK"
    }

    // MARK: Output Stripping

    /// Strip a trailing "OK", "ERROR", or "Command not recognized."
    /// line from command output.
    ///
    /// Maps to netmiko's strip_prompt().
    override public func stripPrompt(_ output: String) -> String {
        let expectPattern = #"^(OK|ERROR|Command not recognized\.)$"#
        var lines = output.components(separatedBy: responseReturn)
        guard let last = lines.last else { return output }
        if last.range(of: expectPattern, options: .regularExpression) != nil {
            lines.removeLast()
            return lines.joined(separator: responseReturn)
        }
        return output
    }

    // MARK: Command Execution

    /// Send a command, defaulting the expected terminating pattern to
    /// this platform's OK/ERROR/unrecognized-command vocabulary
    /// rather than a normal prompt search.
    ///
    /// Maps to netmiko's send_command() override — Python's version
    /// branches on positional vs. keyword args to locate an
    /// already-supplied expect_string; in Swift the named parameter
    /// makes that branch unnecessary, since the caller's value (if
    /// any) is already unambiguous.
    @discardableResult
    override public func sendCommand(
        _ command: String,
        readTimeout: TimeInterval? = nil,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true,
        autoFindPrompt: Bool = true
    ) async throws -> String {
        let resolvedExpectString = expectString ?? {
            let basePattern = #"(OK|ERROR|Command not recognized\.)"#
            return profile.returnCharacter + basePattern + profile.returnCharacter
        }()

        return try await super.sendCommand(
            command,
            readTimeout: readTimeout,
            expectString: resolvedExpectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand
        )
    }

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Cisco TC/CE does not support saveConfig()"
        )
    }
}
