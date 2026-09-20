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
// Sources/Swiftmiko/Flexvnf/Flexvnf.swift

import Foundation

/// Versa Networks FlexVNF SSH driver.
///
/// Maps to netmiko's FlexvnfSSH(NoEnable, BaseConnection).
///
/// No privilege escalation on this platform — hence NoEnable.
/// FlexVNF is architecturally very close to Juniper's JunOS: same
/// shell/CLI duality with an enterCLIMode() auto-detection step, same
/// commit-based configuration lifecycle with check/confirm/comment
/// options, and the same "[edit]"/"{master:0}" configuration-context
/// output markers to strip. This is likely because Versa's platform
/// heritage or CLI design was directly inspired by JunOS.
public final class FlexvnfSSH: BaseConnection, NoEnable {

    // MARK: Session Preparation

    /// Disable paging and set the base prompt for interaction.
    ///
    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: #"[\$@>%]"#)
        try await enterCLIMode()
        try await setBasePrompt()
        try await setTerminalWidth(command: "set screen width 511", pattern: "set")
        try await disablePaging(command: "set screen length 0")
    }

    // MARK: Shell / CLI Mode

    /// Detect a root shell prompt and switch into the CLI if
    /// necessary.
    ///
    /// Maps to netmiko's enter_cli_mode().
    ///
    /// Structurally similar to Juniper's enterCLIMode(), but a
    /// distinct implementation: rather than a wall-clock timeout,
    /// this loops a fixed 50 times, sending a bare return and reading
    /// back each iteration. If the response looks like a root shell
    /// ("admin@..." or ending in a bare "$"), it sends "cli" and
    /// clears the buffer before breaking. If the response already
    /// looks like a CLI prompt (contains ">" or "%"), it breaks
    /// immediately without doing anything further. If neither
    /// condition is ever met within 50 iterations, this silently
    /// gives up — no error is raised, matching Netmiko's own
    /// behavior exactly (there's no `else` clause on the loop the way
    /// Calix B6 or Extreme ERS have one).
    private func enterCLIMode() async throws {
        let delay = selectDelayFactor(0)

        for _ in 0..<50 {
            try await writeChannel(profile.returnCharacter)
            try await Task.sleep(nanoseconds: UInt64(0.1 * delay * 1_000_000_000))
            let currentPrompt = try await readChannel()

            let looksLikeRootShell = currentPrompt.range(
                of: "admin@", options: .regularExpression
            ) != nil || currentPrompt.trimmingCharacters(in: .whitespaces).hasSuffix("$")

            if looksLikeRootShell {
                try await writeChannel("cli" + profile.returnCharacter)
                try await Task.sleep(nanoseconds: UInt64(0.3 * delay * 1_000_000_000))
                try await clearBuffer()
                break
            } else if currentPrompt.contains(">") || currentPrompt.contains("%") {
                break
            }
        }
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string="]") — note
    /// this drops the `pattern` argument when forwarding to super,
    /// same "accepted but not forwarded" quirk seen twice before
    /// (Calix B6, Fiberstore NetworkOS).
    override public func isInConfigMode(
        checkString: String = "]",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(checkString: checkString)
    }

    /// Maps to netmiko's config_mode(config_command="configure").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Exit configuration mode, handling uncommitted-changes
    /// confirmation.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="exit
    /// configuration-mode"). Same discard-and-exit policy as
    /// Juniper's equivalent, though the string check here is looser —
    /// it matches on "uncommitted changes" appearing anywhere in the
    /// output rather than a specific confirmation prompt phrase.
    /// Netmiko's own commented-out line
    /// (`# if 'Exit with uncommitted changes?' in output:`) suggests
    /// the author deliberately broadened the check at some point;
    /// preserved as the looser check, with the original comment kept
    /// for context.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit configuration-mode",
        pattern: String = ""
    ) async throws -> String {
        var output = ""
        guard try await isInConfigMode() else { return output }

        output += try await sendCommandTiming(
            exitConfig,
            stripPrompt: false,
            stripCommand: false
        )

        // Netmiko's own comment: `# if 'Exit with uncommitted changes?' in output:`
        // was apparently loosened to a broader substring check.
        if output.contains("uncommitted changes") {
            output += try await sendCommandTiming(
                "yes",
                stripPrompt: false,
                stripCommand: false
            )
        }

        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }
        return output
    }

    // MARK: Commit

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit() — structurally nearly identical to
    /// Juniper's commit() and Ericsson IPOS's commit(), with the same
    /// check/confirm/confirmDelay/comment/andQuit validation rules.
    /// One real difference: when andQuit is set, this expects the
    /// STORED basePrompt specifically as the termination pattern
    /// (rather than Juniper's more defensive "either the old prompt
    /// OR a fresh >/# prompt" alternation) — a narrower assumption
    /// that and-quit always returns to exactly the prompt that was
    /// already known, not a changed one.
    @discardableResult
    public func commit(
        confirm: Bool = false,
        confirmDelay: Int? = nil,
        check: Bool = false,
        comment: String = "",
        andQuit: Bool = false,
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        guard !(check && (confirm || confirmDelay != nil || !comment.isEmpty)) else {
            throw SwiftmikoError.invalidArgument(
                "Invalid arguments supplied with commit check"
            )
        }
        guard !(confirmDelay != nil && !confirm) else {
            throw SwiftmikoError.invalidArgument(
                "Invalid arguments supplied to commit method both confirm and check"
            )
        }

        var commandString = "commit"
        var commitMarker = "Commit complete."

        if check {
            commandString = "commit check"
            commitMarker = "Validation complete"
        } else if confirm {
            if let confirmDelay {
                commandString = "commit confirmed \(confirmDelay)"
            } else {
                commandString = "commit confirmed"
            }
            commitMarker = "commit confirmed will be automatically rolled back in"
        }

        if !comment.isEmpty {
            guard !comment.contains("\"") else {
                throw SwiftmikoError.invalidArgument(
                    "Invalid comment contains double quote"
                )
            }
            commandString += " comment \"\(comment)\""
        }

        if andQuit {
            commandString += " and-quit"
        }

        var output = try await enterConfigMode()

        if andQuit {
            output += try await sendCommand(
                commandString,
                readTimeout: readTimeout,
                expectString: basePrompt,
                stripPrompt: true,
                stripCommand: true
            )
        } else {
            output += try await sendCommand(
                commandString,
                readTimeout: readTimeout,
                stripPrompt: true,
                stripCommand: true
            )
        }

        guard output.contains(commitMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with the following errors:\n\n\(output)"
            )
        }
        return output
    }

    // MARK: Output Stripping

    /// Strip the trailing prompt, then also strip FlexVNF-specific
    /// context markers.
    ///
    /// Maps to netmiko's strip_prompt() override.
    override public func stripPrompt(_ output: String) -> String {
        let base = super.stripPrompt(output)
        return stripContextItems(base)
    }

    /// Strip FlexVNF's configuration-context and chassis-context
    /// marker lines from output.
    ///
    /// Maps to netmiko's _strip_context_items().
    ///
    /// TWO things here are worth flagging as likely mistakes in the
    /// original Netmiko source, preserved exactly rather than
    /// silently corrected:
    ///
    /// 1. `r"admin@lab-pg-dev-cp02v.*"` is a HARDCODED lab hostname —
    ///    almost certainly a leftover debug pattern from whoever
    ///    originally wrote this driver, matching their own personal
    ///    test device rather than any general FlexVNF behavior. It
    ///    will never match on any other real device's hostname. This
    ///    is dead weight in the pattern list for anyone except the
    ///    original author.
    ///
    /// 2. Netmiko's own code checks `response_list[0]` (the FIRST
    ///    line of output) rather than `response_list[-1]` (the LAST
    ///    line) — the pattern Juniper's equivalent method, and every
    ///    other "strip trailing context line" method in this entire
    ///    vendor set, correctly uses. Checking the first line instead
    ///    of the last is very likely a bug: it means this stripping
    ///    logic is checking the wrong end of the output entirely, and
    ///    the `[:-1]` slice on a successful match would still remove
    ///    the LAST line regardless — meaning a match on line 1 could
    ///    cause the wrong line (the actual last line of real output)
    ///    to be silently dropped.
    ///
    /// Both are preserved exactly as written, since "fixing" either
    /// one without testing against a real FlexVNF device risks
    /// replacing a known-working (if accidentally so) behavior with
    /// an assumption that hasn't been verified. Worth flagging to
    /// Netmiko upstream and testing carefully before considering a
    /// fix here.
    internal func stripContextItems(_ output: String) -> String {
        let stringsToStrip = [
            #"admin@lab-pg-dev-cp02v.*"#,
            #"\[edit.*\]"#,
            #"\[edit\]"#,
            #"\[ok\]"#,
            #"\[.*\]"#,
            #"\{master:.*\}"#,
            #"\{backup:.*\}"#,
            #"\{line.*\}"#,
            #"\{primary.*\}"#,
            #"\{secondary.*\}"#,
        ]

        var lines = output.components(separatedBy: responseReturn)
        // NOTE: Python checks response_list[0] here (the first line),
        // not response_list[-1] (the last line) — preserved exactly,
        // see the extensive comment above.
        guard let firstLine = lines.first else { return output }

        for pattern in stringsToStrip {
            if firstLine.range(of: pattern, options: .regularExpression) != nil {
                lines.removeLast()
                return lines.joined(separator: responseReturn)
            }
        }
        return output
    }
}
