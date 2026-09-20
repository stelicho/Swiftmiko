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
// Sources/Swiftmiko/PaloAlto/PaloAltoPanos.swift

import Foundation

/// Keyboard-interactive SSH authentication handler for PAN-OS
/// devices.
///
/// Maps to netmiko's SSHClient_interactive(SSHClient), specifically
/// its pa_banner_handler and overridden _auth().
///
/// This is a genuinely different authentication mechanism from the
/// "no-auth" transport pattern used by SG200, Calix B6, Dell
/// PowerConnect, Ericsson MiniLink, and Fiberstore FSOS elsewhere in
/// this vendor set. Those devices either always report success
/// regardless of credentials, or don't support password auth at the
/// SSH protocol level at all. PAN-OS is different again: it uses
/// standard SSH "keyboard-interactive" authentication (RFC 4256),
/// where the SERVER drives a sequence of named prompts and the
/// CLIENT answers each one. PAN-OS's own prompts commonly include a
/// EULA-style "Do you accept the terms..." banner alongside the
/// normal password prompt — both need answering in the SAME
/// interactive exchange, which standard password auth has no
/// mechanism for at all.
///
/// This represents a genuine, separate architectural requirement:
/// Swiftmiko's transport layer needs to support keyboard-interactive
/// auth with a pluggable prompt-answering callback, not just
/// password/key/agent/no-auth. Worth designing as its own case
/// rather than folding into the existing no-auth-transport backlog
/// item, since the underlying SSH mechanism is fundamentally
/// different.
public struct PaloAltoInteractiveAuthHandler {
    private let password: String

    public init(password: String) {
        self.password = password
    }

    /// Answer each server-supplied prompt in a keyboard-interactive
    /// exchange.
    ///
    /// Maps to netmiko's pa_banner_handler(title, instructions,
    /// prompt_list).
    ///
    /// For each (prompt, echo) pair the server sends, this responds
    /// "yes" to anything resembling a terms-acceptance banner, and
    /// the connection's password to anything resembling a password
    /// prompt. Any prompt matching neither pattern is left
    /// unanswered — mirroring Netmiko's own behavior, which silently
    /// skips prompts it doesn't recognize rather than guessing.
    public func respond(
        title: String,
        instructions: String,
        prompts: [(prompt: String, echo: Bool)]
    ) -> [String] {
        var responses: [String] = []
        for (prompt, _) in prompts {
            if prompt.contains("Do you accept") {
                responses.append("yes")
            } else if prompt.contains("ssword") {
                responses.append(password)
            }
        }
        return responses
    }
}

/// Common implementation for Palo Alto Networks PAN-OS devices (both
/// SSH and Telnet).
///
/// Maps to netmiko's PaloAltoPanosBase(NoEnable, BaseConnection).
///
/// No privilege escalation via enable mode on this platform — hence
/// NoEnable, and per Netmiko's own docstring, enable()/
/// check_enable_mode() are explicitly disabled.
open class PaloAltoPanosBase: BaseConnection, NoEnable {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Two paging-related calls, back to back, for two DIFFERENT
    /// purposes: the first ("set cli scripting-mode on") switches
    /// PAN-OS into a machine-friendly output mode, waited on with a
    /// pattern combining the prompt AND the confirmation text "mode
    /// on" — the second ("set cli pager off") is the more
    /// conventional pagination toggle. Both are routed through
    /// disablePaging() despite doing genuinely different things, same
    /// "overloaded disablePaging" pattern Juniper used.
    ///
    /// The trailing "show system info" probe at the end is worth
    /// calling out specifically: Netmiko's own comment says "PA
    /// devices can be really slow — try to make sure we are caught
    /// up." This isn't checking anything meaningful about the
    /// device's actual state; it's a deliberate settle/sync step,
    /// firing a real command and waiting for BOTH a known substring
    /// in its output ("operational-mode") AND the prompt reappearing,
    /// purely to give a slow device time to finish whatever it was
    /// doing before session prep considers itself complete.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: promptPattern)

        try await disablePaging(
            command: "set cli scripting-mode on",
            cmdVerify: false,
            pattern: "\(promptPattern).*mode on"
        )
        try await setTerminalWidth(
            command: "set cli terminal width 500",
            pattern: "set cli terminal width 500"
        )
        try await disablePaging(command: "set cli pager off")
        try await setBasePrompt()

        // PA devices can be really slow — make sure we're caught up
        // before considering session prep complete.
        try await writeChannel("show system info\n")
        _ = try await testChannelRead(pattern: "operational-mode")
        _ = try await testChannelRead(pattern: promptPattern)
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's find_prompt() — PA devices can be very slow
    /// to respond in certain situations, per Netmiko's own comment;
    /// this override exists mainly to supply the default pattern
    /// rather than adding new timing logic of its own.
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.findPrompt(delay: delay, pattern: pattern ?? promptPattern)
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="]").
    override public func isInConfigMode(
        checkString: String = "]",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Maps to netmiko's config_mode(config_command="configure",
    /// pattern=r"#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "#",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's exit_config_mode(exit_config="exit",
    /// pattern=r">").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ">"
    ) async throws -> String {
        return try await super.exitConfigMode(
            exitConfig: exitConfig,
            pattern: pattern
        )
    }

    // MARK: Commit

    /// Commit the candidate configuration, with rich support for
    /// PAN-OS's partial-commit scoping options.
    ///
    /// Maps to netmiko's commit() — the most elaborate commit
    /// command-string construction in this entire vendor set. Every
    /// scoping flag (deviceAndNetwork, policyAndObjects, vsys,
    /// noVsys) is only valid when `partial` is true, checked up
    /// front. Command string is built incrementally: optional
    /// quoted comment, optional "force", then if partial, "partial"
    /// followed by whichever combination of scope flags were
    /// supplied, always terminated with "excluded" when in partial
    /// mode. Waits for "100%" specifically in the response (PAN-OS's
    /// own progress-percentage output) as the completion signal
    /// before checking for the actual success marker.
    @discardableResult
    public func commit(
        comment: String = "",
        force: Bool = false,
        partial: Bool = false,
        deviceAndNetwork: Bool = false,
        policyAndObjects: Bool = false,
        vsys: String = "",
        noVsys: Bool = false,
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        guard partial || !(deviceAndNetwork || policyAndObjects || !vsys.isEmpty || noVsys) else {
            throw SwiftmikoError.invalidArgument(
                "'partial' must be True when using deviceAndNetwork or " +
                "policyAndObjects or vsys or noVsys."
            )
        }

        var commandString = "commit"
        let commitMarker = "configuration committed successfully"

        if !comment.isEmpty {
            commandString += " description \"\(comment)\""
        }
        if force {
            commandString += " force"
        }
        if partial {
            commandString += " partial"
            if !vsys.isEmpty {
                commandString += " \(vsys)"
            }
            if deviceAndNetwork {
                commandString += " device-and-network"
            }
            if policyAndObjects {
                commandString += " policy-and-objects"
            }
            if noVsys {
                commandString += " no-vsys"
            }
            commandString += " excluded"
        }

        var output = try await enterConfigMode()
        output += try await sendCommand(
            commandString,
            readTimeout: readTimeout,
            expectString: "100%",
            stripPrompt: false,
            stripCommand: false
        )
        output += try await exitConfigMode()

        guard output.lowercased().contains(commitMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }
        return output
    }

    // MARK: Output Stripping

    /// Strip the trailing router prompt from output, using a
    /// distinctly more aggressive strategy than most drivers in this
    /// vendor set.
    ///
    /// Maps to netmiko's strip_prompt() override.
    ///
    /// UNLIKE nearly every other driver here (which only strip the
    /// LAST line if it matches the prompt), this filters OUT EVERY
    /// LINE anywhere in the output that contains basePrompt as a
    /// substring — a meaningfully different and more aggressive
    /// approach. Worth being cautious with: if a command's legitimate
    /// output happens to contain the base prompt string as
    /// incidental text (unlikely but not impossible — e.g. a
    /// hostname appearing in a log line), this would silently remove
    /// that line too, not just the actual trailing prompt.
    override public func stripPrompt(_ output: String) -> String {
        let lines = output.components(separatedBy: responseReturn)
        let filtered = lines.filter { !$0.contains(basePrompt) }
        let cleaned = filtered.joined(separator: responseReturn)
        return stripContextItems(cleaned)
    }

    /// Strip Palo Alto's configuration-context marker line from
    /// output.
    ///
    /// Maps to netmiko's strip_context_items(). PAN-OS appends a
    /// "[edit]" context line, similar to Juniper's and FlexVNF's
    /// equivalent markers — stripped if it appears as the trailing
    /// line.
    internal func stripContextItems(_ output: String) -> String {
        let pattern = #"\[edit.*\]"#
        var lines = output.components(separatedBy: responseReturn)
        guard let lastLine = lines.last else { return output }

        if lastLine.range(of: pattern, options: .regularExpression) != nil {
            lines.removeLast()
            return lines.joined(separator: responseReturn)
        }
        return output
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit"). Same
    /// pattern="" / timing-based check_config_mode() nuance as
    /// Nokia SR OS's cleanup — forcing the timing-based path
    /// specifically during teardown.
    override public func cleanup(command: String = "exit") async throws {
        do {
            if try await isInConfigMode(pattern: "") {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }
}

// MARK: - PaloAltoPanosSSH

/// Palo Alto PAN-OS SSH driver.
///
/// Maps to netmiko's PaloAltoPanosSSH(PaloAltoPanosBase).
///
/// Uses keyboard-interactive SSH authentication when neither keys nor
/// agent auth were requested — see PaloAltoInteractiveAuthHandler
/// above for the full explanation of why this is architecturally
/// distinct from the no-auth transport pattern used elsewhere.
public final class PaloAltoPanosSSH: PaloAltoPanosBase {

    /// Maps to netmiko's _get_ssh_client_instance().
    /// Signals that keyboard-interactive auth (via
    /// PaloAltoInteractiveAuthHandler) should be used for this
    /// connection, rather than standard password authentication —
    /// distinct from every prior driver's "use noauth" signal.
    internal func requiresInteractiveAuth() -> Bool {
        switch profile.auth {
        case .keyFile, .sshAgent:
            return false
        case .password, .none:
            return true
        }
    }
}

// MARK: - PaloAltoPanosTelnet

/// Palo Alto PAN-OS Telnet driver — no differences from the base.
/// Maps to netmiko's PaloAltoPanosTelnet(PaloAltoPanosBase).
public final class PaloAltoPanosTelnet: PaloAltoPanosBase {}
