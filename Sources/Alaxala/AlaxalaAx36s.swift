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
// Sources/Swiftmiko/Alaxala/AlaxalaAx36s.swift

import Foundation

/// ALAXALA AX36S SSH driver base.
///
/// Maps to netmiko's AlaxalaAx36sBase(CiscoSSHConnection).
open class AlaxalaAx36sBase: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.disable_paging(command="set terminal pager disable")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: 300_000_000)
        try await disablePaging(command: "set terminal pager disable")
    }

    // MARK: Prompt Detection

    /// Detect the base prompt, then strip the leading character.
    ///
    /// Maps to netmiko's set_base_prompt(), which does
    /// `self.base_prompt = base_prompt[1:]` after calling super —
    /// the opposite operation from Cisco IOS's trailing truncation.
    /// ALAXALA apparently prefixes the detected prompt with a
    /// character (likely a device-type or context indicator) that
    /// shouldn't be part of the stored delimiter used for stripping
    /// prompts from command output.
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        guard !basePrompt.isEmpty else { return }
        basePrompt = String(basePrompt.dropFirst())
    }

    // MARK: Config Mode

    /// Exit configuration mode, handling the unsaved-changes prompt.
    ///
    /// Maps to netmiko's exit_config_mode(exit_command="end").
    ///
    /// If there are unsaved changes, the device asks:
    ///     Unsaved changes found! Do you exit "configure" without
    ///     save ? (y/n):
    /// This always answers "y" — discard and exit without saving.
    /// Same policy as Viptela's and Yamaha's equivalent prompts:
    /// saving is always the caller's explicit responsibility via
    /// saveConfig(), never an implicit side effect of exiting.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "end",
        pattern: String = ""
    ) async throws -> String {
        var output = ""
        guard try await isInConfigMode() else { return output }

        try await writeChannel(normalizeCommand(exitConfig))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        output = try await readChannel()

        if output.contains("(y/n)") {
            try await writeChannel("y\n")
        }
        if !output.contains(basePrompt) {
            output += try await readUntilPrompt(readEntireLine: true)
        }
        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit config mode.")
        }
        return output
    }

    // MARK: Save Config

    /// Save the running configuration.
    ///
    /// Maps to netmiko's save_config(cmd="write").
    ///
    /// Must run from inside config mode — the device indicates
    /// unsaved changes with a leading "!" in the prompt, though this
    /// driver doesn't parse that indicator directly; it just ensures
    /// config mode is entered, sends the write command followed by a
    /// bare return, and exits again. Uses sendCommandTiming rather
    /// than sendCommand throughout, since the write confirmation
    /// output doesn't reliably terminate with a clean, matchable
    /// prompt on the first pass.
    override public func saveConfig(
        command: String = "write",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        var output = ""
        if try await !isInConfigMode() {
            _ = try await enterConfigMode()
        }

        output = try await sendCommandTiming(
            command,
            stripPrompt: false,
            stripCommand: false
        )
        output += try await sendCommandTiming(
            profile.returnCharacter,
            stripPrompt: false,
            stripCommand: false
        )

        _ = try await exitConfigMode()

        if !output.contains(basePrompt) {
            output += try await readUntilPrompt(readEntireLine: true)
        }
        return output
    }
}

// MARK: - AlaxalaAx36sSSH

/// ALAXALA AX36S SSH driver — no differences from the base.
/// Maps to netmiko's AlaxalaAx36sSSH(AlaxalaAx36sBase).
public final class AlaxalaAx36sSSH: AlaxalaAx36sBase {}
