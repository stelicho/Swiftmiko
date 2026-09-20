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
// Sources/Swiftmiko/HP/HPProcurve.swift

import Foundation

/// Common implementation for HP ProCurve switches.
///
/// Maps to netmiko's HPProcurveBase(CiscoSSHConnection).
///
/// The most defensively-written login/enable sequence in this
/// vendor set after Furukawa FITELnet — ProCurve devices are known
/// (per HP's own comment) to fail connections more often than
/// expected, and present login output in an unusual order that can
/// confuse naive prompt detection.
open class HPProcurveBase: CiscoSSHConnection {

    /// Increase the connection timeout, and restrict RSA-SHA2 public
    /// key algorithms unless the caller has already configured their
    /// own restrictions.
    ///
    /// Maps to netmiko's __init__ override:
    ///     conn_timeout = kwargs.get("conn_timeout")
    ///     kwargs["conn_timeout"] = 20 if conn_timeout is None else conn_timeout
    ///     disabled_algorithms = kwargs.get("disabled_algorithms")
    ///     if disabled_algorithms is None:
    ///         disabled_algorithms = {"pubkeys": ["rsa-sha2-256", "rsa-sha2-512"]}
    ///         kwargs["disabled_algorithms"] = disabled_algorithms
    ///
    /// Same translation approach as Fortinet's KEX restriction: rather
    /// than trying to reconstruct Paramiko's private default pubkey
    /// algorithm list and subtract from it, this expresses the
    /// restriction directly as "these specific algorithms are
    /// disallowed" on the profile, which the transport layer is
    /// expected to honor during the SSH handshake's public-key
    /// algorithm negotiation. See the disabledPublicKeyAlgorithms
    /// backlog note — this is the second driver needing transport-
    /// level crypto negotiation control, after Fortinet's KEX case.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.connectionTimeout == 10 {
            // 10 is BaseConnection's documented default — only
            // override if the caller hasn't already customized it.
            adjustedProfile.connectionTimeout = 20
        }
        if adjustedProfile.disabledPublicKeyAlgorithms == nil {
            adjustedProfile.disabledPublicKeyAlgorithms = ["rsa-sha2-256", "rsa-sha2-512"]
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
    /// ProCurve has a genuinely odd quirk HP's own comment describes:
    /// the router prompt can show up BEFORE the "Press any key to
    /// continue" message — meaning a naive implementation that just
    /// waits for the prompt could stop reading too early, missing the
    /// key-press requirement entirely. This reads past the copyright
    /// banner first (tolerating a timeout if no banner appears at
    /// all — some ProCurve configurations skip it), then separately
    /// checks for and answers the "any key" prompt if it shows up.
    ///
    /// Both reads are wrapped so a timeout is treated as a
    /// non-fatal "this step didn't apply to this session" signal
    /// rather than aborting connection setup — a real behavioral
    /// nuance worth preserving exactly, since some ProCurve firmware
    /// versions simply don't show these banners at all.
    override public func sessionPreparation() async throws {
        // HP output contains VT100 escape codes.
        ansiEscapeCodes = true

        do {
            _ = try await readUntilPattern(pattern: ".*opyright", timeout: 1.3)
        } catch is SwiftmikoError {
            // No copyright banner appeared — not fatal, continue.
        }

        do {
            let data = try await readUntilPattern(
                pattern: "(any key to continue|[>#])",
                timeout: 3.0
            )
            if data.contains("any key to continue") {
                try await writeChannel(profile.returnCharacter)
                _ = try await readUntilPattern(pattern: "[>#]", timeout: 3.0)
            }
        } catch is SwiftmikoError {
            // No "any key" prompt appeared — not fatal, continue.
        }

        try await setBasePrompt()
        // If the prompt still looks odd (suspiciously long), try
        // detecting it a second time.
        if basePrompt.count >= 25 {
            try await setBasePrompt()
        }

        // ProCurve requires elevated privileges to disable output
        // paging — an unfortunate platform limitation HP's own
        // comment laments outright.
        try await enterEnableMode(secret: profile.secret ?? "")
        try await setTerminalWidth(command: "terminal width 511", pattern: "terminal")
        try await disablePaging(command: "no page")
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern=r"[>#]").
    ///
    /// HP's own comment explains why the pattern argument matters
    /// here specifically: without it, each isInConfigMode() call would
    /// take roughly two seconds longer, since the base class's
    /// default has no pattern to anchor the read against.
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Enable Mode

    /// Enter enable mode, with an optional username sub-step some
    /// ProCurve configurations require.
    ///
    /// Maps to netmiko's enable(cmd="enable", pattern="password",
    /// re_flags=re.IGNORECASE, default_username="").
    ///
    /// This is a genuinely hand-rolled implementation, not a forward
    /// to a generic enable flow — ProCurve can prompt for a SEPARATE
    /// username at the enable step (distinct from the login
    /// username), which most drivers in this vendor set never
    /// encounter. The read pattern narrows progressively: first waits
    /// for username-or-password-or-prompt, then (if a username
    /// request appeared) narrows to password-or-prompt, then (if a
    /// password request appeared) waits for the final prompt alone.
    /// `defaultUsername` falls back to the connection's own login
    /// username if the caller doesn't supply a distinct one for the
    /// enable step.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "password",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        if checkState, try await isInEnableMode() {
            return ""
        }

        let resolvedUsername = defaultUsername.isEmpty ? profile.username : defaultUsername

        var output = ""
        let usernamePattern = "(username|login|user name)"
        let passwordPattern = pattern
        let promptPattern = "[>#]"
        var fullPattern = "(username|login|user name|\(passwordPattern)|\(promptPattern))"

        try await writeChannel(command + profile.returnCharacter)
        var newOutput = try await readUntilPattern(
            pattern: fullPattern,
            timeout: 15.0,
            caseInsensitive: caseInsensitive
        )

        // Send the username, if requested.
        if newOutput.range(
            of: usernamePattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil {
            output += newOutput
            try await writeChannel(resolvedUsername + profile.returnCharacter)
            fullPattern = "(\(passwordPattern)|\(promptPattern))"
            newOutput = try await readUntilPattern(
                pattern: fullPattern,
                timeout: 15.0,
                caseInsensitive: caseInsensitive
            )
        }

        // Send the password.
        if newOutput.range(
            of: passwordPattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil {
            output += newOutput
            try await writeChannel(secret + profile.returnCharacter)
            newOutput = try await readUntilPattern(
                pattern: promptPattern,
                timeout: 15.0,
                caseInsensitive: caseInsensitive
            )
        }

        output += newOutput
        logger.debug("\(output)")
        try await clearBuffer()

        guard try await isInEnableMode() else {
            throw SwiftmikoError.authenticationFailed(
                "Failed to enter enable mode. Please ensure you pass " +
                "the 'secret' argument to ConnectHandler."
            )
        }
        return output
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session, handling ProCurve's
    /// logout/save confirmation prompts.
    ///
    /// Maps to netmiko's cleanup(command="logout").
    ///
    /// Best-effort exit-config-mode first, swallowing any error, then
    /// sends the logout command and loops (up to 10 times, with a
    /// short read timeout each pass) watching for two distinct
    /// confirmation questions: "Do you want to log out" (answered
    /// "y" — proceed) and "Do you want to save the current..."
    /// (answered "n" — do NOT auto-save; saving remains the caller's
    /// explicit responsibility). Any read/socket error during this
    /// loop breaks out immediately rather than retrying, since the
    /// connection may already be dead by that point.
    override public func cleanup(command: String = "logout") async throws {
        do {
            if try await isInConfigMode() {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }

        try await writeChannel(command + profile.returnCharacter)

        for _ in 0..<10 {
            do {
                let pattern = "Do you want.*"
                let newOutput = try await readUntilPattern(pattern: pattern, timeout: 1.5)

                if newOutput.contains("Do you want to log out") {
                    try await writeChannel("y" + profile.returnCharacter)
                    break
                } else if newOutput.contains("Do you want to save the current") {
                    // Don't automatically save the config — that
                    // remains the caller's responsibility.
                    try await writeChannel("n" + profile.returnCharacter)
                }
            } catch {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        sessionLog?.fin = true
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory").
    override public func saveConfig(
        command: String = "write memory",
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

// MARK: - HPProcurveSSH

/// HP ProCurve SSH driver.
///
/// Maps to netmiko's HPProcurveSSH(HPProcurveBase).
///
/// Uses a no-auth transport ONLY when no keys, no agent, AND no
/// password have been supplied at all — a narrower condition than
/// every other no-auth-transport driver in this vendor set (SG200,
/// Calix B6, Dell PowerConnect, Ericsson MiniLink, Fiberstore FSOS),
/// which all treat plain password auth as sufficient reason to use
/// noauth. ProCurve's own check requires the ABSENCE of a password
/// too — meaning this driver expects password auth to go through
/// normally, and only falls back to noauth for a genuinely
/// credential-less connection attempt.
public final class HPProcurveSSH: HPProcurveBase {

    /// Maps to netmiko's _get_ssh_client_instance().
    /// See the no-auth transport gap discussion, now confirmed a
    /// sixth time — but note the narrower trigger condition described
    /// above, distinct from every prior occurrence.
    internal func requiresNoAuthTransport() -> Bool {
        switch profile.auth {
        case .keyFile, .sshAgent, .password:
            return false
        case .none:
            return true
        }
    }
}

// MARK: - HPProcurveTelnet

/// HP ProCurve Telnet driver.
///
/// Maps to netmiko's HPProcurveTelnet(HPProcurveBase).
public final class HPProcurveTelnet: HPProcurveBase {

    /// Telnet login: can be username/password, or password-only on
    /// some configurations.
    ///
    /// Maps to netmiko's telnet_login(pri_prompt_terminator="#",
    /// alt_prompt_terminator=">", username_pattern=r"(Login Name:|
    /// sername:)", pwd_pattern=r"assword", max_loops=60).
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(Login Name:|sername:)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 60
    ) async throws -> String {
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
