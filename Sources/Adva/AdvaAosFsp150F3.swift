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
// Sources/Swiftmiko/Adva/AdvaAosFsp150F3.swift

import Foundation

/// Adva AOS FSP 150 F3 SSH driver.
///
/// Maps to netmiko's AdvaAosFsp150F3SSH(NoEnable, NoConfig,
/// CiscoSSHConnection).
///
/// F3 AOS applies to FSP150CC-XG21x, FSP150CC-GE11x, and
/// FSP150CC-GE20x. Like F2, there is no Enable Mode or Config Mode —
/// configuration goes through the same directory-style context
/// system:
///
///     home
///     configure communication
///     add ip-route nexthop xxxxxxx
///     home
///     network-element ne-1
///
/// F3 differs from F2 in three concrete ways: it handles a
/// "--More--" pagination prompt during login that F2 doesn't
/// encounter, it has a genuine (if unusual) mechanism for disabling
/// paging via a multi-command config sequence, and its
/// sendConfigSet() carries Adva-specific safety defaults around which
/// commands are allowed to echo verification output.
public final class AdvaAosFsp150F3SSH: CiscoSSHConnection, NoEnable, NoConfig {

    /// Same "\r\n" line-ending requirement as F2.
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

    // MARK: Session Preparation

    /// Handles devices with a security prompt enabled, AND a
    /// "--More--" pagination interstitial that can appear before the
    /// prompt settles.
    ///
    /// Maps to netmiko's session_preparation():
    ///     data = self.read_until_pattern(pattern=r"Do you wish to
    ///         continue [Y|N]-->|-->")
    ///     if "continue" in data:
    ///         self.write_channel(f"y{self.RETURN}")
    ///     else:
    ///         self.write_channel(f"home{self.RETURN}")
    ///     data = self.read_until_pattern(pattern=r"-->|--More--")
    ///     if "--More--" in data:
    ///         self.write_channel(self.RETURN)
    ///     self.set_base_prompt()
    ///     self.write_channel(self.RETURN)
    ///     self.disable_paging(cmd_verify=False)
    ///
    /// Note F3 sends "home" rather than F2's "help?" in the no-prompt
    /// branch — a small but real behavioral difference between the
    /// two firmware families, not an inconsistency to "fix."
    override public func sessionPreparation() async throws {
        var data = try await readUntilPattern(
            pattern: #"Do you wish to continue \[Y\|N\]-->|-->"#
        )
        if data.contains("continue") {
            try await writeChannel("y" + profile.returnCharacter)
        } else {
            try await writeChannel("home" + profile.returnCharacter)
        }

        data = try await readUntilPattern(pattern: "-->|--More--")

        if data.contains("--More--") {
            try await writeChannel(profile.returnCharacter)
        }

        try await setBasePrompt()
        try await writeChannel(profile.returnCharacter)
        try await disablePaging(cmdVerify: false)
    }

    // MARK: Paging

    /// Disable paging via a multi-line configuration sequence.
    ///
    /// Maps to netmiko's disable_paging() — unusually, this doesn't
    /// send a single "no pager"-style command. It has to navigate
    /// into a specific configuration context, disable paging for the
    /// current user by name, and navigate back out:
    ///
    ///     configure user-security
    ///     config-user <username> cli-paging disabled
    ///     home
    ///
    /// The `command` parameter exists purely for interface parity
    /// with the base class's disablePaging signature — passing a
    /// non-empty value is treated as a caller error, since this
    /// driver's paging-disable sequence is fixed and not
    /// user-overridable.
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        guard command.isEmpty else {
            throw SwiftmikoError.invalidArgument(
                "Unexpected value for command in disablePaging(): \(command)"
            )
        }

        let commands = [
            "configure user-security",
            "config-user \(profile.username) cli-paging disabled",
            "home"
        ]
        return try await sendConfigSet(commands, cmdVerify: cmdVerify)
    }

    // MARK: Prompt Detection

    /// Identical logic to AdvaAosFsp150F2SSH.setBasePrompt() — both
    /// F2 and F3 share the same "-->"-terminator detection and
    /// validation scheme. Duplicated here rather than factored into a
    /// shared helper to keep this file a direct 1:1 mirror of its
    /// Python source; worth extracting into a shared internal
    /// extension (e.g. AdvaPromptDetection) once both files are
    /// tested and stable.
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

        if prompt.count == 1 {
            basePrompt = prompt
        } else {
            basePrompt = trailingThree
        }
    }

    // MARK: Config Set

    /// Send a set of configuration commands with Adva F3's specific
    /// safety defaults.
    ///
    /// Maps to netmiko's send_config_set() override — by far the
    /// largest parameter surface seen in this vendor set so far.
    ///
    /// The one piece of genuine logic here (rather than parameter
    /// forwarding) is `bypassCommands`: when the caller doesn't
    /// supply one, this builds a regex matching certain sensitive
    /// command shapes — adding a superuser/crypto/maintenance/
    /// provisioning/retrieve/test-user account, or anything
    /// containing "secret" — so that command-echo verification is
    /// bypassed for those lines specifically. Presumably these
    /// commands either don't echo cleanly or contain content (like a
    /// password) that shouldn't be checked against the sent command
    /// text.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = false,
        readTimeout: TimeInterval? = 2.0,
        maxLoops: Int? = nil,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = false,
        errorPattern: String = "",
        terminator: String = "-->",
        bypassCommands: String? = nil
    ) async throws -> String {
        let resolvedBypassCommands: String
        if let bypassCommands {
            resolvedBypassCommands = bypassCommands
        } else {
            let categories = "(?:superuser|crypto|maintenance|provisioning|retrieve|test-user)"
            resolvedBypassCommands =
                #"(?:add\s+\S+\s+\S+\s+\S+\s+\#(categories)|secret.*)"#
        }

        return try await super.sendConfigSet(
            commands,
            exitConfigMode: exitConfigMode,
            readTimeout: readTimeout,
            maxLoops: maxLoops,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            configModeCommand: configModeCommand,
            cmdVerify: cmdVerify,
            enterConfigMode: enterConfigMode,
            errorPattern: errorPattern,
            terminator: terminator,
            bypassCommands: resolvedBypassCommands
        )
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="logout").
    override public func cleanup(command: String = "logout") async throws {
        try await super.cleanup(command: command)
    }
}
