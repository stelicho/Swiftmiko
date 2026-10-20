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
//
//  CiscoASA.swift
//  Swiftmiko
//
import Foundation

/// Cisco ASA (Adaptive Security Appliance) SSH driver.
///
/// Maps to netmiko's CiscoAsaSSH(CiscoSSHConnection).
public class CiscoASASSH: CiscoSSHConnection {

    /// Cisco ASA always allows automatic device changes (used by
    /// sessionPreparation()'s terminal-width step below), overriding
    /// the normal profile-wide default.
    ///
    /// Maps to netmiko's __init__ override:
    ///     kwargs.setdefault("allow_auto_change", True)
    public override init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        logLabel: String = "swiftmiko",
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil,
        globalCmdVerify: Bool? = nil
    ) {
        var adjustedProfile = profile
        adjustedProfile.allowAutoChange = true
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            logLabel: logLabel,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider,
            globalCmdVerify: globalCmdVerify
        )
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// The "show curpriv\n" probe (note the literal embedded "\n",
    /// not profile.returnCharacter — carried over exactly as real
    /// Netmiko hardcodes it) makes sure the ASA is ready before
    /// anything else happens. Privilege level 15 can then be reached
    /// one of two ways depending on how the connection was
    /// configured: a secret triggers the normal enable() flow, while
    /// its absence falls back to asaLogin()'s "login" prompt sequence
    /// instead. Terminal width is only ever attempted when
    /// allowAutoChange is set (forced true by this class's own init
    /// above, but still overridable by a caller who explicitly
    /// disables it afterward) — if it isn't, cmdVerify is disabled
    /// globally instead, since without a known terminal width the
    /// device's echo behavior becomes unreliable to verify against.
    override public func sessionPreparation() async throws {
        let command = "show curpriv\n"
        try await writeChannel(command)
        _ = try await readUntilPattern(
            pattern: NSRegularExpression.escapedPattern(
                for: command.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )

        try await setBasePrompt()
        if let secret = profile.secret, !secret.isEmpty {
            try await enterEnableMode(secret: secret)
        } else {
            try await asaLogin()
        }
        try await disablePaging(command: "terminal pager 0")

        if profile.allowAutoChange {
            do {
                _ = try await sendConfigSet(["terminal width 511"])
            } catch {
                // Don't fail for the terminal width.
            }
        } else {
            setGlobalCmdVerify(false)
        }

        try await setBasePrompt()
    }

    // MARK: Enable Mode

    /// Maps to netmiko's enable(cmd="enable", pattern="ssword",
    /// enable_pattern=r"\#", re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = "\\#",
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        return try await super.enterEnableMode(
            secret: secret,
            command: command,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive,
            defaultUsername: defaultUsername
        )
    }

    // MARK: ASA Login (no-secret fallback)

    /// Handle ASA reaching privilege level 15 via "login" instead of
    /// "enable", for connections with no secret configured.
    ///
    /// Maps to netmiko's asa_login():
    ///     twb-dc-fw1> login
    ///     Username: admin
    ///
    /// Throws after 10 unanswered loop iterations, matching real
    /// Netmiko's own attempt cap.
    private func asaLogin() async throws {
        let delay = selectDelayFactor(0)

        try await writeChannel("login" + profile.returnCharacter)
        _ = try await readUntilPattern(pattern: "login")

        for _ in 1...10 {
            try await Task.sleep(nanoseconds: UInt64(0.5 * delay * 1_000_000_000))
            let output = try await readChannel()

            if output.contains("sername") {
                try await writeChannel(profile.username + profile.returnCharacter)
            } else if output.contains("ssword") {
                guard case .password(let password) = profile.auth else {
                    throw SwiftmikoError.authenticationFailed(
                        "ASA login requires password authentication"
                    )
                }
                try await writeChannel(password + profile.returnCharacter)
            } else if output.contains("#") {
                return
            } else {
                try await writeChannel("login" + profile.returnCharacter)
            }
        }

        throw SwiftmikoError.authenticationFailed("Unable to enter enable mode!")
    }

    // MARK: Multi-Context Prompt Tracking
    //
    // ASA in multi-context mode needs the base prompt re-detected
    // after a context switch ("changeto ..."). Maps to netmiko's
    // send_command()/send_command_timing() overrides.

    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        // Let the parent detect the prompt normally
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        // ASA multi-context: strip trailing (conf... from prompt
        // e.g. "fw1(config)" → "fw1"
        let detected = basePrompt
        if let match = detected.range(of: #"^(.*)\(conf"#, options: .regularExpression) {
            if let regex = try? NSRegularExpression(pattern: #"^(.*)\(conf"#),
               let m = regex.firstMatch(in: detected, range: NSRange(detected.startIndex..., in: detected)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: detected) {
                basePrompt = String(detected[r])
            }
            _ = match
        }
    }

    /// Maps to netmiko's send_command() override — forces a "#" wait
    /// when the caller didn't supply their own expectString, since a
    /// "changeto" command invalidates whatever prompt pattern was
    /// previously being waited on.
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
        var resolvedExpectString = expectString
        if command.contains("changeto"), resolvedExpectString == nil {
            resolvedExpectString = "#"
        }
        let output = try await super.sendCommand(
            command,
            readTimeout: readTimeout,
            expectString: resolvedExpectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            cmdVerify: cmdVerify,
            autoFindPrompt: autoFindPrompt
        )
        // Multi-context: re-detect prompt after every context switch
        if command.contains("changeto") {
            try await setBasePrompt()
        }
        return output
    }

    /// Maps to netmiko's send_command_timing() override — same
    /// re-detect-prompt-after-changeto behavior as sendCommand()
    /// above, for the timing-based send path.
    @discardableResult
    override public func sendCommandTiming(
        _ command: String,
        readTimeout: TimeInterval = 2.0,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true
    ) async throws -> String {
        let output = try await super.sendCommandTiming(
            command,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            cmdVerify: cmdVerify
        )
        if command.contains("changeto") {
            try await setBasePrompt()
        }
        return output
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write mem").
    @discardableResult
    override public func saveConfig(
        command: String = "write mem",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // ASA has unusual \r\n\r sequences
    override public func normalizeLinefeeds(_ input: String) -> String {
        var result = input
        for pattern in ["\r\n\r", "\r\r\r\n", "\r\r\n", "\r\n", "\n\r"] {
            result = result.replacingOccurrences(of: pattern, with: responseReturn)
        }
        if responseReturn == "\n" {
            result = result.replacingOccurrences(of: "\r", with: "")
        }
        return result
    }
}

// MARK: - CiscoAsaFileTransfer

/// Cisco ASA SCP File Transfer driver — no differences from the base.
/// Maps to netmiko's CiscoAsaFileTransfer(CiscoFileTransfer).
///
/// Unlike cisco_ios/cisco_xe/cisco_xr, ASA is NOT one of the device
/// types SCPHandler's own init autodetects a file system for — real
/// Netmiko's BaseFileTransfer has the exact same restriction, so a
/// caller must always supply fileSystem explicitly for ASA transfers.
public final class CiscoAsaFileTransfer: CiscoFileTransfer {}
