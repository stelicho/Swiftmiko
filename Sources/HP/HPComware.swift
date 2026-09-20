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
// Sources/Swiftmiko/HP/HPComware.swift

import Foundation

/// Common implementation for HP Comware devices.
///
/// Maps to netmiko's HPComwareBase(CiscoSSHConnection).
///
/// The defining trait of this driver: Comware has no privilege
/// escalation concept at all. HP's own comments state it plainly,
/// three separate times: "enable mode on Comware is system-view."
/// Rather than a genuine privileged/unprivileged distinction, this
/// driver aliases enable(), exitEnableMode(), and isInEnableMode()
/// directly onto their config-mode equivalents.
open class HPComwareBase: CiscoSSHConnection {

    /// Comware has no way to set a terminal width, which breaks
    /// command-echo verification for long commands — this forces
    /// globalCmdVerify off unless the caller's profile already
    /// specifies it.
    ///
    /// Maps to netmiko's __init__ override:
    ///     global_cmd_verify = kwargs.get("global_cmd_verify")
    ///     if global_cmd_verify is None:
    ///         kwargs["global_cmd_verify"] = False
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        super.init(
            profile: profile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
        setGlobalCmdVerify(false)
    }

    // MARK: Session Preparation

    /// Handle Comware's optional continue-banner, then prepare the
    /// session normally.
    ///
    /// Maps to netmiko's session_preparation().
    ///
    /// Comware can present "Press Y or ENTER to continue, N to exit."
    /// before allowing login to proceed — detected and answered with
    /// a bare newline if it appears.
    override public func sessionPreparation() async throws {
        let data = try await testChannelRead(pattern: #"to continue|[>\]]"#)
        if data.contains("continue") {
            try await writeChannel("\n")
            _ = try await testChannelRead(pattern: #"[>\]]"#)
        }

        try await setBasePrompt()
        try await disablePaging(command: "screen-length disable")
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="system-view").
    @discardableResult
    override public func enterConfigMode(
        command: String = "system-view",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="return",
    /// pattern=r">").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "return",
        pattern: String = ">"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    /// Maps to netmiko's check_config_mode(check_string="]",
    /// pattern=r"[>\]]").
    override public func isInConfigMode(
        checkString: String = "]",
        pattern: String = #"[>\]]"#
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Config Set

    /// Maps to netmiko's send_config_set() — a thin forward with
    /// Comware-specific defaults (terminator matching "]" rather than
    /// a plain "#").
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
        readTimeout: TimeInterval? = nil,
        maxLoops: Int? = nil,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = true,
        errorPattern: String = "",
        terminator: String = #"\]"#,
        bypassCommands: String? = nil
    ) async throws -> String {
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
            bypassCommands: bypassCommands
        )
    }

    // MARK: Prompt Handling

    /// Refresh the buffer after an auto-find-prompt lookup, clearing
    /// any residual prompt fragment Comware can leave queued.
    ///
    /// Maps to netmiko's _prompt_handler(auto_find_prompt).
    ///
    /// HP's own comment: "Comware can leave a <HOSTNAME> prompt
    /// fragment queued after find_prompt(). Clear the residual prompt
    /// so send_command() reads the real command output." Without
    /// this, a subsequent sendCommand() call could misread a stale
    /// prompt echo as part of the actual command's output.
    override public func promptHandler(autoFindPrompt: Bool) async -> String {
        let prompt = await super.promptHandler(autoFindPrompt: autoFindPrompt)
        if autoFindPrompt {
            try? await clearBuffer()
        }
        return prompt
    }

    // MARK: Prompt Detection

    /// Detect the base prompt, stripping Comware's bracket/angle
    /// delimiters and any high-availability firewall prefix.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator="]").
    ///
    /// Comware prompts look like "<HOSTNAME>" (user view) or
    /// "[HOSTNAME]" (system view). This strips the leading
    /// delimiter character entirely (rather than the trailing one
    /// most drivers strip), leaving just the bare hostname as
    /// basePrompt — general enough to match in either view. It also
    /// strips a leading "RBM_." prefix some HA firewall
    /// configurations add to the hostname before the real name
    /// begins.
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = "]",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )

        // Strip off any leading RBM_. characters for firewall HA.
        var prompt = basePrompt.replacingOccurrences(
            of: #"^RBM_."#,
            with: "",
            options: [.regularExpression]
        )

        // Strip off the leading delimiter character (< or [).
        if !prompt.isEmpty {
            prompt = String(prompt.dropFirst())
        }
        basePrompt = prompt.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Enable Mode — Aliased to Config Mode

    /// Enable mode on Comware is system-view.
    /// Maps to netmiko's enable(cmd="system-view", pattern="ssword",
    /// re_flags=re.IGNORECASE) — forwards directly to
    /// enterConfigMode() rather than doing any real privilege
    /// escalation, since there is none on this platform.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "system-view",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        return try await enterConfigMode(command: command)
    }

    /// Enable mode on Comware is system-view.
    /// Maps to netmiko's exit_enable_mode(exit_command="return") —
    /// forwards directly to exitConfigMode().
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "return"
    ) async throws -> String {
        return try await exitConfigMode(exitConfig: exitCommand)
    }

    /// Enable mode on Comware is system-view.
    /// Maps to netmiko's check_enable_mode(check_string="]") —
    /// forwards directly to isInConfigMode().
    override public func isInEnableMode(
        checkString: String = "]"
    ) async throws -> Bool {
        return try await isInConfigMode(checkString: checkString)
    }

    // MARK: Cleanup

    /// Maps to netmiko's cleanup(command="quit").
    override public func cleanup(command: String = "quit") async throws {
        try await super.cleanup(command: command)
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save force").
    override public func saveConfig(
        command: String = "save force",
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

// MARK: - HPComwareSSH

/// HP Comware SSH driver — no differences from the base.
/// Maps to netmiko's HPComwareSSH(HPComwareBase).
public final class HPComwareSSH: HPComwareBase {}

// MARK: - HPComwareTelnet

/// HP Comware Telnet driver.
/// Maps to netmiko's HPComwareTelnet(HPComwareBase). Overrides the
/// default line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class HPComwareTelnet: HPComwareBase {

    override public init(
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
        setGlobalCmdVerify(false)
    }
}
