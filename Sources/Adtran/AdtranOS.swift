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
// Sources/Swiftmiko/Adtran/AdtranOS.swift

import Foundation

/// Common implementation for Adtran OS devices (both SSH and Telnet).
///
/// Maps to netmiko's AdtranOSBase(CiscoBaseConnection).
///
/// The most elaborate enable-mode implementation seen in this vendor
/// set so far — it handles a device-specific "falling back to local
/// authentication" flow where the secret may need to be sent twice.
open class AdtranOSBase: CiscoBaseConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="terminal length 0")
    ///     cmd = "terminal width 132"
    ///     self.set_terminal_width(command=cmd, pattern=cmd)
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
        try await disablePaging(command: "terminal length 0")
        let widthCommand = "terminal width 132"
        try await setTerminalWidth(command: widthCommand, pattern: widthCommand)
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Enter enable mode, handling Adtran's local-authentication
    /// fallback flow.
    ///
    /// Maps to netmiko's enable(cmd="enable", pattern="ssword",
    /// re_flags=re.IGNORECASE) — the most involved translation in
    /// this file. The sequence is:
    ///
    ///   1. Return immediately if already enabled.
    ///   2. Send "enable" and read the command echo.
    ///   3. Wait for either a trailing prompt or a password prompt.
    ///   4. If a password prompt appeared, send the secret.
    ///   5. Watch specifically for "Falling back" in the response —
    ///      some Adtran configurations attempt a remote auth method
    ///      first (e.g. RADIUS/TACACS+), and only fall back to
    ///      checking the local secret if that remote attempt fails.
    ///      When that fallback message appears, the secret must be
    ///      sent a SECOND time for the local check.
    ///   6. Confirm the device actually reached enable mode; if not,
    ///      raise a clear error pointing at the missing `secret`
    ///      argument rather than a generic timeout.
    ///
    /// A timeout anywhere in this sequence is deliberately converted
    /// into the same clear "did you forget secret?" error rather than
    /// surfacing a raw timeout — that's almost always the actual root
    /// cause in practice.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        let failureMessage =
            "Failed to enter enable mode. Please ensure you pass " +
            "the 'secret' argument to ConnectHandler."

        var output = ""

        if checkState, try await isInEnableMode() {
            return output
        }

        do {
            try await writeChannel(normalizeCommand(command))

            if cmdVerifyEnabled {
                output += try await readUntilPattern(
                    pattern: NSRegularExpression.escapedPattern(
                        for: command.trimmingCharacters(in: .whitespaces)
                    )
                )
            }

            output += try await readUntilPromptOrPattern(
                pattern: pattern,
                readEntireLine: true
            )

            if output.range(
                of: pattern,
                options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
            ) != nil {
                try await writeChannel(normalizeCommand(secret))

                // Watch for the local-auth fallback message. If the
                // device attempted a remote auth method first and
                // failed over to checking the local secret, the
                // secret must be sent again for that second check.
                let fallbackPattern = "Falling back"
                let fallbackOutput = try await readUntilPromptOrPattern(
                    pattern: fallbackPattern,
                    caseInsensitive: caseInsensitive
                )
                output += fallbackOutput

                if fallbackOutput.contains("Falling back") {
                    try await writeChannel(normalizeCommand(secret))
                    output += try await readUntilPrompt()
                }
            }

            if let enablePattern,
               output.range(of: enablePattern, options: .regularExpression) == nil {
                output += try await readUntilPattern(pattern: enablePattern)
            } else {
                guard try await isInEnableMode() else {
                    throw SwiftmikoError.authenticationFailed(failureMessage)
                }
            }
        } catch let error as SwiftmikoError {
            switch error {
            case .timeout:
                throw SwiftmikoError.authenticationFailed(failureMessage)
            default:
                throw error
            }
        }

        return output
    }

    /// Maps to netmiko's exit_enable_mode(exit_command="disable").
    ///
    /// Note the command here — "disable", not "exit". Adtran's
    /// terminology mirrors traditional Unix privilege escalation
    /// rather than the "exit"/"end" vocabulary most Cisco-family
    /// devices use.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "disable"
    ) async throws -> String {
        return try await super.exitEnableMode(exitCommand: exitCommand)
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#").
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="config term").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config term",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="end",
    /// pattern="#").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = "#"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator="#").
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = "#",
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
}

// MARK: - AdtranOSSSH

/// Adtran OS SSH driver — no differences from the base.
/// Maps to netmiko's AdtranOSSSH(AdtranOSBase).
public final class AdtranOSSSH: AdtranOSBase {}

// MARK: - AdtranOSTelnet

/// Adtran OS Telnet driver.
///
/// Maps to netmiko's AdtranOSTelnet(AdtranOSBase). Overrides the
/// default line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class AdtranOSTelnet: AdtranOSBase {

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
}
