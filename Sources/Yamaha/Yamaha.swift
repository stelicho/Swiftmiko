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
// Sources/Swiftmiko/Yamaha/Yamaha.swift

import Foundation

/// Common implementation for Yamaha routers (both SSH and Telnet).
///
/// Maps to netmiko's YamahaBase(BaseConnection).
///
/// Yamaha has only one elevated privilege level, called
/// "Administrator" — entered via the "administrator" command and an
/// interactive password prompt. There is no separate configuration
/// mode layered on top of that: config_mode() and enable() are the
/// same operation. exit_config_mode() is consequently a no-op —
/// exitEnableMode() is the real way to drop back to normal exec.
open class YamahaBase: BaseConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="console lines infinity")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "console lines infinity")
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Enable Mode

    /// Maps to netmiko's check_enable_mode(check_string="#").
    override public func isInEnableMode(
        checkString: String = "#"
    ) async throws -> Bool {
        return try await super.isInEnableMode(checkString: checkString)
    }

    /// Enter Administrator mode.
    ///
    /// Maps to netmiko's enable(cmd="administrator", pattern=r"Password",
    /// re_flags=re.IGNORECASE).
    ///
    /// Yamaha's Administrator command prompts with "Password:" rather
    /// than the more common "ssword" fragment other Cisco-derived
    /// drivers match on, and it's matched case-insensitively since
    /// firmware versions vary in capitalization.
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "administrator",
        pattern: String = "Password",
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

    /// Exit Administrator mode.
    ///
    /// Maps to netmiko's exit_enable_mode() — this is the one method
    /// on this driver with genuinely custom logic rather than just a
    /// parameter forward.
    ///
    /// If any settings changed during this session, Yamaha asks
    /// "Save new configuration ? (Y/N)" before it will actually drop
    /// privilege. This always answers "N" — Swiftmiko's policy, same
    /// as Netmiko's, is that saving is the caller's explicit
    /// responsibility via saveConfig(), never an implicit side effect
    /// of leaving enable mode.
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = "exit"
    ) async throws -> String {
        var output = ""
        guard try await isInEnableMode() else { return output }

        try await writeChannel(normalizeCommand(exitCommand))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        output = try await readChannel()

        if output.contains("(Y/N)") {
            // Decline the save prompt — do not send a line ending,
            // matching Netmiko's bare write_channel("N") exactly.
            try await writeChannel("N")
        }

        if !output.contains(basePrompt) {
            output += try await readUntilPrompt(readEntireLine: true)
        }

        if try await isInEnableMode() {
            throw SwiftmikoError.commandFailed("Failed to exit enable mode.")
        }
        return output
    }

    // MARK: Config Mode

    /// Checks if the device is in Administrator mode.
    ///
    /// Maps to netmiko's check_config_mode(check_string="#", pattern="").
    /// Yamaha has no distinct config-mode prompt shape — "in config
    /// mode" and "in enable mode" are the same "#" check.
    override public func isInConfigMode(
        checkString: String = "#",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Enter configuration mode.
    ///
    /// Maps to netmiko's config_mode(), which does not call the base
    /// implementation at all — it forwards straight to enable() with
    /// the same command and pattern. There is no separate config-mode
    /// transition on this platform; "config mode" IS Administrator
    /// mode.
    @discardableResult
    override public func enterConfigMode(
        command: String = "administrator",
        pattern: String = "Password",
        dotAll: Bool = false
    ) async throws -> String {
        return try await enterEnableMode(
            secret: profile.secret ?? "",
            command: command,
            pattern: pattern,
            caseInsensitive: true
        )
    }

    /// No action taken on exit — matches Netmiko's exit_config_mode(),
    /// which is a deliberate no-op.
    ///
    /// Call exitEnableMode() directly to actually leave Administrator
    /// level. This override exists purely so a generic caller that
    /// always calls exitConfigMode() after sendConfigSet() doesn't
    /// accidentally kick the session out of Administrator mode
    /// mid-workflow.
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ">"
    ) async throws -> String {
        return ""
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="save"). Yamaha's save
    /// command has no confirmation step at all — passing confirm=true
    /// is a caller error, not a supported variant, so it throws
    /// immediately rather than silently ignoring the flag.
    public func saveConfig(
        command: String = "save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        guard !confirm else {
            throw SwiftmikoError.invalidArgument(
                "Yamaha does not support save_config confirmation."
            )
        }
        try await enterEnableMode(secret: profile.secret ?? "")
        return try await sendCommand(command)
    }
}

// MARK: - YamahaSSH

/// Yamaha SSH driver — no differences from the base.
/// Maps to netmiko's YamahaSSH(YamahaBase).
public final class YamahaSSH: YamahaBase {}

// MARK: - YamahaTelnet

/// Yamaha Telnet driver.
///
/// Maps to netmiko's YamahaTelnet(YamahaBase).
///
/// Overrides the default line ending to a bare "\n" rather than the
/// "\r\n" most Telnet drivers use. In Swift this is expressed as a
/// default value on the initializer rather than mutating kwargs,
/// since
