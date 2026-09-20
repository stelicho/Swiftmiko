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
// Sources/Swiftmiko/Huawei/HuaweiSmartAX.swift

import Foundation

/// Huawei SmartAX / OLT SSH driver.
///
/// Maps to netmiko's HuaweiSmartAXSSH(CiscoBaseConnection).
///
/// The most privilege-juggling driver in the whole vendor set: four
/// separate helper methods each temporarily escalate to whatever
/// privilege level a specific tuning command requires, run that
/// command, and then carefully de-escalate back down ONLY if this
/// particular call was the one that escalated in the first place —
/// tracked via local booleans, not a stack, so nested calls must be
/// reasoned about carefully.
public class HuaweiSmartAXSSH: CiscoBaseConnection {

    override public nonisolated var promptPattern: String { "[>$]" }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Huawei OLT firmware can present a "YES/NO" post-login banner
    /// requiring an explicit "yes" before the real prompt appears.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true

        let data = try await testChannelRead(pattern: "YES.NO|\(promptPattern)")
        if data.range(of: "YES.NO", options: .regularExpression) != nil {
            try await writeChannel("yes" + profile.returnCharacter)
            _ = try await testChannelRead(pattern: promptPattern)
        }

        try await setBasePrompt()
        try await disableSmartInteraction()
        try await disableInfoswitchCLI()
        try await disablePaging()
    }

    // MARK: ANSI Handling

    /// Strip Huawei's cursor-left escape sequence, which trails an
    /// unwanted extra space.
    ///
    /// Maps to netmiko's strip_ansi_escape_codes() override.
    ///
    /// Netmiko's own comment explains it well: Huawei emits a space
    /// followed by ESC[<N>D (move cursor left N columns) — presumably
    /// a terminal redraw artifact. The extra space is the actual
    /// problem; stripping only the escape code and leaving the space
    /// behind would still corrupt output.
    override public func stripAnsiEscapeCodes(_ input: String) -> String {
        let cursorLeftCode = "\u{1B}" + #"\[\d+D"#
        let pattern = " " + cursorLeftCode
        let output = input.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
        logger.debug("Stripping ANSI escape codes")
        logger.debug("new_output = \(output)")
        return super.stripAnsiEscapeCodes(output)
    }

    // MARK: MMI Mode

    /// Enter SmartAX's faster machine-to-machine interaction mode.
    ///
    /// Maps to netmiko's _enter_mmi_mode(command="mmi-mode enable").
    ///
    /// mmi-mode requires config mode. If the session isn't already
    /// enabled or in config mode, this escalates through both,
    /// remembering via local flags whether IT was the one that did
    /// the escalating — only THIS call's own escalation gets
    /// unwound afterward, leaving a caller's pre-existing elevated
    /// state untouched.
    internal func enterMMIMode(command: String = "mmi-mode enable") async throws {
        var privEscalationEnable = false
        var privEscalationConfig = false

        if try await !isInEnableMode() {
            try await enterEnableMode(secret: profile.secret ?? "")
            privEscalationEnable = true
        }
        if try await !isInConfigMode() {
            _ = try await enterConfigMode()
            privEscalationConfig = true
        }

        let escapedPrompt = NSRegularExpression.escapedPattern(for: basePrompt)
        _ = try await sendCommand(command, expectString: "\(escapedPrompt)\\(config\\)#")

        if privEscalationConfig {
            _ = try await exitConfigMode()
        }
        if privEscalationEnable {
            _ = try await exitEnableMode()
        }
    }

    /// Exit SmartAX's machine-to-machine interaction mode.
    ///
    /// Maps to netmiko's _disable_mmi_mode(command="mmi-mode disable").
    ///
    /// Note: Netmiko's own Python here calls `self.check_config_mode()`
    /// again inside the `if not self.check_config_mode():` branch
    /// (rather than `self.config_mode()`, which is what actually
    /// enters config mode) — this looks like a copy-paste bug in the
    /// original, since it means privEscalationConfig can be set true
    /// without config mode actually having been entered. Preserved
    /// EXACTLY as written rather than silently corrected, since
    /// "fixing" it could change behavior in ways that haven't been
    /// tested against a real device — but flagged clearly here as a
    /// likely upstream bug worth reporting.
    internal func disableMMIMode(command: String = "mmi-mode disable") async throws {
        var privEscalationEnable = false
        var privEscalationConfig = false

        if try await !isInEnableMode() {
            try await enterEnableMode(secret: profile.secret ?? "")
            privEscalationEnable = true
        }
        if try await !isInConfigMode() {
            // NOTE: Netmiko calls check_config_mode() again here,
            // not config_mode() — likely a bug, preserved as-is.
            _ = try await isInConfigMode()
            privEscalationConfig = true
        }

        let escapedPrompt = NSRegularExpression.escapedPattern(for: basePrompt)
        _ = try await sendCommand(command, expectString: "\(escapedPrompt)(config)#")

        if privEscalationConfig {
            _ = try await exitConfigMode()
        }
        if privEscalationEnable {
            _ = try await exitEnableMode()
        }
    }

    /// Disable debugging output being sent to the terminal by
    /// default.
    ///
    /// Maps to netmiko's _disable_infoswitch_cli(command="infoswitch
    /// cli OFF"). Requires only enable mode, not config mode — a
    /// simpler single-level escalation than the MMI methods above.
    internal func disableInfoswitchCLI(command: String = "infoswitch cli OFF") async throws {
        var privEscalation = false

        if try await !isInEnableMode() {
            try await enterEnableMode(secret: profile.secret ?? "")
            privEscalation = true
        }

        let escapedPrompt = NSRegularExpression.escapedPattern(for: basePrompt)
        _ = try await sendCommand(command, expectString: "\(escapedPrompt)#")

        if privEscalation {
            _ = try await exitEnableMode()
        }
    }

    /// Disable the "{ <cr> }" confirmation prompt, avoiding the need
    /// to send a second return after every command.
    ///
    /// Maps to netmiko's _disable_smart_interaction(command="undo
    /// smart", delay_factor=1.0).
    ///
    /// Sent via a direct writeChannel/read pair rather than through
    /// sendCommand — this needs fine control over whether to wait for
    /// the command echo at all, gated on the CURRENT cmdVerifyEnabled
    /// state (unlike most drivers, which just always or never wait).
    internal func disableSmartInteraction(
        command: String = "undo smart",
        delay: TimeInterval = 1.0
    ) async throws {
        let resolvedDelay = selectDelayFactor(delay)
        try await Task.sleep(nanoseconds: UInt64(resolvedDelay * 0.1 * 1_000_000_000))
        try await clearBuffer()

        let normalizedCommand = normalizeCommand(command)
        logger.debug("In disableSmartInteraction")
        logger.debug("Command: \(normalizedCommand)")
        try await writeChannel(normalizedCommand)

        var output = ""
        if cmdVerifyEnabled {
            _ = try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(
                    for: normalizedCommand.trimmingCharacters(in: .whitespaces)
                )
            )
            output = try await readUntilPrompt(readEntireLine: true)
        } else {
            output = try await readUntilPrompt(readEntireLine: true)
        }
        logger.debug("\(output)")
        logger.debug("Exiting disableSmartInteraction")
    }

    // MARK: Paging

    /// Maps to netmiko's disable_paging(command="scroll").
    @discardableResult
    override public func disablePaging(
        command: String = "scroll",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.disablePaging(command: command, pattern: pattern)
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="config",
    /// pattern=r"\)#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "config",
        pattern: String = #"\)#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(command: command, pattern: pattern)
    }

    /// Maps to netmiko's check_config_mode(check_string="\\)#",
    /// pattern="[#>]", force_regex=true).
    override public func isInConfigMode(
        checkString: String = #"\)#"#,
        pattern: String = "[#>]"
    ) async throws -> Bool {
        return try await isInConfigModeRegex(checkString: checkString, pattern: pattern)
    }

    /// Maps to netmiko's exit_config_mode(exit_config="return",
    /// pattern=r"#.*").
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "return",
        pattern: String = "#.*"
    ) async throws -> String {
        return try await super.exitConfigMode(exitConfig: exitConfig, pattern: pattern)
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Maps to netmiko's enable(cmd="enable", re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "",
        enablePattern: String? = nil,
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
            caseInsensitive: caseInsensitive
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

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save").
    override public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session, forcing logout if the device
    /// doesn't cooperate within a timeout.
    ///
    /// Maps to netmiko's cleanup(command="quit").
    ///
    /// Runs the base cleanup sequence first, then actively polls for
    /// up to 30 seconds watching for either a logout confirmation
    /// prompt (answered "y") or a message indicating the console
    /// already exited. Checks isAlive() before every read — if the
    /// session is already gone, this returns immediately rather than
    /// reading from a dead channel. If neither terminal condition is
    /// ever reached within the timeout, this throws rather than
    /// silently giving up on a logout that may never have happened.
    override public func cleanup(command: String = "quit") async throws {
        try await super.cleanup(command: command)

        let timeout: TimeInterval = 30
        let startTime = Date()
        var output = ""

        while Date().timeIntervalSince(startTime) < timeout {
            guard await isAlive() else { return }

            output += try await readChannel()

            if output.contains("Are you sure to log out? (y/n)[n]:") {
                try await writeChannel("y" + profile.returnCharacter)
                output = ""
            } else if output.contains("Configuration console exit, please retry to log on") {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        throw SwiftmikoError.commandFailed("Failed to log out of the device")
    }
}

// MARK: - HuaweiSmartAXSSHMMI

/// Huawei SmartAX SSH driver with MMI mode enabled automatically
/// during session preparation.
///
/// Maps to netmiko's HuaweiSmartAXSSHMMI(HuaweiSmartAXSSH).
public final class HuaweiSmartAXSSHMMI: HuaweiSmartAXSSH {

    override public func sessionPreparation() async throws {
        try await super.sessionPreparation()
        try await enterMMIMode()
    }
}
