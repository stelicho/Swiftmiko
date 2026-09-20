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
// Sources/Swiftmiko/Adva/AdvaAosFsp150F2.swift

import Foundation

/// Adva AOS FSP 150 F2 SSH driver.
///
/// Maps to netmiko's AdvaAosFsp150F2SSH(NoEnable, NoConfig,
/// CiscoSSHConnection).
///
/// F2 AOS applies to FSP150CC-825 and similar device types. These
/// devices have no Enable Mode and no Config Mode in the traditional
/// sense — configuration is applied through a directory-like context
/// system instead:
///
///     home
///     configure snmp
///     add v3user guytest noauth-nopriv
///     home
///
///     configure system
///     home
///
/// "home" returns to the CLI root context. Calling "home" from the
/// root itself produces "Unrecognized command" — there's no error
/// suppression for that in this driver; it's the caller's
/// responsibility to track context depth.
public final class AdvaAosFsp150F2SSH: CiscoSSHConnection, NoEnable, NoConfig {

    /// Adva devices require "\r\n" as the line ending for proper
    /// operation — this is forced unless the caller's profile
    /// already specifies a return character explicitly.
    ///
    /// Maps to netmiko's __init__ override:
    ///     if kwargs.get("default_enter") is None:
    ///         kwargs["default_enter"] = "\r\n"
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

    // MARK: Session Preparation

    /// Handles devices with a security prompt enabled at login.
    ///
    /// Maps to netmiko's session_preparation():
    ///     data = self.read_until_pattern(pattern=r"Do you wish to
    ///         continue [Y|N]-->|-->")
    ///     if "continue" in data:
    ///         self.write_channel(f"y{self.RETURN}")
    ///     else:
    ///         self.write_channel(f"help?{self.RETURN}")
    ///     data = self.read_until_pattern(pattern=r"-->")
    ///     self.set_base_prompt()
    ///
    /// Note the branch when no security prompt appears: the device
    /// sends "help?" rather than a blank return. That's not a typo —
    /// it's apparently how Netmiko nudges an already-ready prompt to
    /// redisplay cleanly on this platform.
    override public func sessionPreparation() async throws {
        let data = try await readUntilPattern(
            pattern: #"Do you wish to continue \[Y\|N\]-->|-->"#
        )
        if data.contains("continue") {
            try await writeChannel("y" + profile.returnCharacter)
        } else {
            try await writeChannel("help?" + profile.returnCharacter)
        }
        _ = try await readUntilPattern(pattern: "-->")
        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Detect the base prompt using Adva's "-->" terminator.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="-->",
    /// alt_prompt_terminator="").
    ///
    /// Unlike most drivers, this builds its own search pattern from
    /// the terminator strings directly (escaping them for regex
    /// safety) rather than delegating that to the base
    /// implementation, and then validates the result by checking that
    /// the prompt's last three characters actually match one of the
    /// supplied terminators — "-->" is three characters, so this is a
    /// direct sanity check, not an approximation.
    override public func setBasePrompt(
        primaryTerminator: String = "-->",
        altTerminator: String = "",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        var searchPattern = pattern

        if searchPattern == nil {
            if !primaryTerminator.isEmpty && !altTerminator.isEmpty {
                let priEscaped = NSRegularExpression.escapedPattern(for: primaryTerminator)
                let altEscaped = NSRegularExpression.escapedPattern(for: altTerminator)
                searchPattern = "(\(priEscaped)|\(altEscaped))"
            } else if !primaryTerminator.isEmpty {
                searchPattern = NSRegularExpression.escapedPattern(for: primaryTerminator)
            } else if !altTerminator.isEmpty {
                searchPattern = NSRegularExpression.escapedPattern(for: altTerminator)
            }
        }

        let prompt: String
        if let searchPattern {
            prompt = try await findPrompt(delay: delay, pattern: searchPattern)
        } else {
            prompt = try await findPrompt(delay: delay)
        }

        let trailingThree = String(prompt.suffix(3))
        guard trailingThree == primaryTerminator || trailingThree == altTerminator else {
            throw SwiftmikoError.unexpectedPrompt(
                "Router prompt not found: \(prompt.debugDescription)"
            )
        }

        // If all we have is the bare terminator, use that as-is —
        // there's no hostname prefix to strip.
        if prompt.count == 1 {
            basePrompt = prompt
        } else {
            basePrompt = trailingThree
        }
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="logout").
    override public func cleanup(command: String = "logout") async throws {
        try await super.cleanup(command: command)
    }
}
