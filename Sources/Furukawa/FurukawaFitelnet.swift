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
// Sources/Swiftmiko/Furukawa/FurukawaFitelnet.swift

import Foundation

/// Common methods for Furukawa FITELnet VPN routers.
///
/// Maps to netmiko's FurukawaFitelnetBase(CiscoBaseConnection).
///
/// FITELnet prompts vary by model:
///   - Bare prompts: ">" (user mode), "#" (enable mode)
///   - Hostname prompts: "F220>", "F220#", "F220(config)#",
///     "F220(config-GigaEthernet1/1)#", etc.
///
/// This driver is unusually defensive compared to most in this
/// vendor set — nearly every override exists to dodge a specific,
/// named failure mode rather than just matching a different command
/// string. Worth reading the comments on each method, since they
/// explain *why* the override is needed, not just *what* it does.
open class FurukawaFitelnetBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Note setBasePrompt() is called TWICE — once before enable(),
    /// once after. This isn't redundant: entering enable mode changes
    /// the bare prompt character from ">" to "#", so the prompt
    /// captured before enable() would be stale immediately afterward.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        // Re-detect base prompt after enable — the bare prompt
        // character changes from ">" to "#".
        try await setBasePrompt()
        try await disablePaging(command: "no more")
    }

    // MARK: Telnet/Serial Login

    /// Telnet/Serial login for FITELnet.
    ///
    /// Maps to netmiko's telnet_login().
    ///
    /// FITELnet emits `<WARNING> weak login password: set the
    /// password` right after login. The base class's default
    /// password pattern (a loose "assword" substring match) would
    /// match the word "password" INSIDE that warning banner and
    /// incorrectly send the actual password as if it were a CLI
    /// command in response to it. Anchoring the pattern to
    /// "assword:\s*$" — a real password prompt ending the line —
    /// avoids that false match.
    @discardableResult
    override public func telnetLogin(
        primaryTerminator: String = #"\#\s*$"#,
        altTerminator: String = #">\s*$"#,
        usernamePattern: String = #"(?:user:|username|login|user name)"#,
        passwordPattern: String = #"assword:\s*$"#,
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
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

    // MARK: Enable Mode

    /// Check if in enable mode.
    ///
    /// Maps to netmiko's check_enable_mode(check_string="#").
    ///
    /// FITELnet uses bare prompts (just ">" or "#"), so this matches
    /// the prompt character specifically at end-of-line to avoid
    /// false-matching on `<WARNING>` / `<ERROR>` banner messages that
    /// happen to contain a literal ">" character somewhere in their
    /// text.
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)
        let output = try await readUntilPattern(pattern: #"[>#]\s*$"#)
        return output.contains(checkString)
    }

    /// Enter enable mode on FITELnet.
    ///
    /// Maps to netmiko's enable(cmd="enable", pattern="ssword",
    /// re_flags=re.IGNORECASE).
    ///
    /// Overridden for two concrete reasons:
    ///
    /// 1. The bare prompt changes from ">" to "#" after enable,
    ///    which would cause a default read_until_prompt()-style wait
    ///    to fail since it's still watching for the OLD prompt
    ///    character.
    ///
    /// 2. If the wrong enable password is supplied, the device
    ///    responds with `<ERROR> Authentication failed` followed by
    ///    ANOTHER password prompt rather than an immediate rejection.
    ///    A naive implementation would hang forever waiting for "#"
    ///    that will never arrive. This override watches for the
    ///    failure string explicitly and throws immediately instead of
    ///    hanging.
    ///
    /// `enablePattern` is accepted for interface parity with the
    /// standard signature but genuinely unused here — this override
    /// hardcodes its own success/failure detection patterns rather
    /// than taking them as configurable parameters.
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
        var output = ""
        if checkState, try await isInEnableMode() {
            return output
        }

        try await writeChannel(normalizeCommand(command))
        output += try await readUntilPattern(
            pattern: "(?:\(pattern)|#)",
            caseInsensitive: caseInsensitive
        )

        if output.range(
            of: pattern,
            options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
        ) != nil {
            try await writeChannel(normalizeCommand(secret))
            // Read until "#" (success) or "Authentication failed"
            // (wrong password) — never wait indefinitely for a
            // prompt that a rejected password will never produce.
            output += try await readUntilPattern(pattern: "(?:#|Authentication failed)")
            guard !output.contains("Authentication failed") else {
                throw SwiftmikoError.authenticationFailed(
                    "Failed to enter enable mode. The enable password " +
                    "(secret) was rejected by the device."
                )
            }
        }

        guard try await isInEnableMode() else {
            throw SwiftmikoError.authenticationFailed(
                "Failed to enter enable mode. Please ensure you pass " +
                "the 'secret' argument to ConnectHandler."
            )
        }
        return output
    }

    /// Exit enable mode on FITELnet.
    ///
    /// Maps to netmiko's exit_enable_mode(exit_command="disable").
    ///
    /// Overridden because the generic implementation waits for "#",
    /// but after sending "disable" the prompt changes to ">" —
    /// waiting for the old prompt character here would hang exactly
    /// the same way enable()'s naive path would.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "disable"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        output += try await readUntilPattern(pattern: #">\s*$"#)

        // Drain any remaining data — serial ports in particular may
        // have buffered echoes still trickling in after the prompt
        // technically matched.
        try await Task.sleep(nanoseconds: 500_000_000)
        try await clearBuffer()

        guard try await !isInEnableMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }

    // MARK: Commit

    /// Commit the candidate configuration, applying working.cfg to
    /// current.cfg.
    ///
    /// Maps to netmiko's commit(read_timeout=120.0).
    ///
    /// Commit may prompt with a "[y/n]"-style confirmation, which is
    /// answered "y" if it appears. Separately from the generic
    /// error-detection at the end, this specifically watches for
    /// FITELnet's "Another processing is executing" busy-message —
    /// worth calling out that this message contains NEITHER "error"
    /// NOR "failed", so the generic case-insensitive error check
    /// below would never catch it on its own; it has to be detected
    /// as its own distinct failure case first. The generic check
    /// afterward specifically matches FITELnet's all-caps `<ERROR>`
    /// tag case-insensitively.
    @discardableResult
    public func commit(readTimeout: TimeInterval = 120.0) async throws -> String {
        var output = ""
        let confirmation = #"onfirm|\[y/[nN]\]"#
        let pattern = "(?:#|\(confirmation))"

        var newData = try await sendCommand(
            "commit",
            readTimeout: readTimeout,
            expectString: pattern,
            stripPrompt: false,
            stripCommand: false
        )

        if newData.range(of: confirmation, options: .regularExpression) != nil {
            output += newData
            newData = try await sendCommand(
                "y",
                readTimeout: readTimeout,
                expectString: "#",
                stripPrompt: false,
                stripCommand: false,
                cmdVerify: false
            )
        }

        output += newData

        // FITELnet refuses to commit while another session/process
        // is active, replying "Another processing is executing. This
        // command can not be executed." This message contains
        // neither "error" nor "failed", so it must be detected here
        // BEFORE the generic case-insensitive check below — that
        // check would never catch this on its own.
        guard !output.contains("Another processing is executing") else {
            throw SwiftmikoError.commandFailed(
                "Commit failed: another process is executing on the device. " +
                "Retry once the other operation completes."
            )
        }

        // FITELnet emits <ERROR> in all caps — match case-insensitively.
        guard output.range(
            of: "error|failed",
            options: [.regularExpression, .caseInsensitive]
        ) == nil else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }

        return output
    }

    // MARK: Save Config

    /// Save working.cfg to boot.cfg (startup configuration).
    ///
    /// Maps to netmiko's save_config(cmd="save", confirm=true,
    /// confirm_response="y").
    ///
    /// FITELnet prompts "save ok?[y/N]:" by default. If another
    /// process is holding the config (e.g. a concurrent session
    /// mid-commit/save/refresh), FITELnet replies with the same
    /// "Another processing is executing" busy-message and never
    /// prints the "[y/N]" prompt at all — meaning the base class's
    /// generic confirm/confirmResponse machinery would send "y" as a
    /// bare, out-of-context CLI command instead of a confirmation
    /// response, since it has no way to know the prompt it expected
    /// never actually appeared. This detects that specific busy state
    /// after the fact and throws a clear error rather than letting
    /// a stray "y" get silently sent to the device.
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = true,
        confirmResponse: String = "y"
    ) async throws -> String {
        let output = try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
        guard !output.contains("Another processing is executing") else {
            throw SwiftmikoError.commandFailed(
                "save_config failed: another process is executing on the device. " +
                "Retry once the other operation completes."
            )
        }
        return output
    }

    // MARK: Output Stripping

    /// Strip the trailing router prompt from output, repeatedly.
    ///
    /// Maps to netmiko's strip_prompt().
    ///
    /// The generic base implementation only removes a SINGLE trailing
    /// prompt line. FITELnet devices — especially over serial or
    /// Telnet — can echo the prompt multiple times in a row, leaving
    /// several trailing prompt/blank lines that a single-pass strip
    /// wouldn't fully clean up. This loops, stripping one trailing
    /// line at a time, until a line is encountered that ISN'T a
    /// recognized prompt shape.
    ///
    /// Control characters (like a bell character, \x07) are stripped
    /// from each candidate line before comparison, since a device
    /// echo can carry those alongside the actual prompt text and
    /// would otherwise prevent an exact match against the known-valid
    /// prompt set.
    ///
    /// Once a real match is found, the valid-prompt set narrows to
    /// JUST that matched shape for subsequent iterations — meaning if
    /// the trailing lines are a mix of, say, both "#" and ">" (which
    /// shouldn't really happen in practice, but the check is
    /// defensive), only a consistent run of the SAME prompt character
    /// gets stripped, not an alternating mix.
    override public func stripPrompt(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmed.components(separatedBy: responseReturn)
        let base = basePrompt.trimmingCharacters(in: .whitespaces)
        var validPrompts: Set<String> = ["#", ">", "\(base)#", "\(base)>"]

        while !lines.isEmpty {
            let lastLine = lines[lines.count - 1].trimmingCharacters(in: .whitespaces)

            // Remove control characters (e.g. BEL \x07) before matching.
            let cleanLine = lastLine.replacingOccurrences(
                of: #"[\x00-\x1f\x7f]"#,
                with: "",
                options: .regularExpression
            )

            if validPrompts.contains(cleanLine) {
                lines.removeLast()
                validPrompts = [cleanLine]
            } else {
                break
            }
        }

        return lines.joined(separator: responseReturn)
    }
}

// MARK: - FurukawaFitelnetSSH

/// Furukawa FITELnet SSH driver — no differences from the base.
/// Maps to netmiko's FurukawaFitelnetSSH(FurukawaFitelnetBase).
public final class FurukawaFitelnetSSH: FurukawaFitelnetBase {}

// MARK: - FurukawaFitelnetTelnet

/// Furukawa FITELnet Telnet driver — no differences from the base.
/// Maps to netmiko's FurukawaFitelnetTelnet(FurukawaFitelnetBase).
public final class FurukawaFitelnetTelnet: FurukawaFitelnetBase {}

// MARK: - FurukawaFitelnetSerial

/// Furukawa FITELnet Serial (console) driver — no differences from
/// the base.
///
/// Maps to netmiko's FurukawaFitelnetSerial(FurukawaFitelnetBase).
///
/// Netmiko's own comment explains why no separate login override is
/// needed here despite this being a distinct transport: `serialLogin()`
/// ultimately calls through to `telnetLogin()` internally, so the
/// telnetLogin() override defined on the shared base above is
/// automatically reused by the Serial variant too — the same reason
/// Cisco IOS's `CiscoIOSSerial` needed no overrides of its own.
public final class FurukawaFitelnetSerial: FurukawaFitelnetBase {}
