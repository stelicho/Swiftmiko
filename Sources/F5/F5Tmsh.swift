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
// Sources/Swiftmiko/F5/F5Tmsh.swift

import Foundation

/// F5 BIG-IP TMSH (Traffic Management Shell) SSH driver.
///
/// Maps to netmiko's F5TmshSSH(NoConfig, BaseConnection).
///
/// TMSH is F5's own configuration shell, entered from the base Linux
/// prompt. Netmiko's own comment is worth repeating verbatim: "tmsh
/// command is equivalent to config command on F5" — meaning tmshMode()
/// below plays the role most drivers give to enterConfigMode(), which
/// is why session preparation calls it unconditionally rather than
/// leaving it as something a caller opts into later. No separate
/// config-mode concept beyond entering tmsh itself — hence NoConfig.
public final class F5TmshSSH: BaseConnection, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"#")
    ///     self.tmsh_mode()
    ///     self._config_mode = False
    ///     cmd = 'run /util bash -c "stty cols 255"'
    ///     self.set_terminal_width(command=cmd, pattern="run")
    ///     self.disable_paging(command="modify cli preference pager disabled display-threshold 0")
    ///
    /// The direct `self._config_mode = False` assignment in Python is
    /// worth explaining rather than glossing over: it's resetting an
    /// internal state flag directly, bypassing any method, right
    /// after tmshMode() has already run. Since entering tmsh could be
    /// mistaken by generic base-class logic for "now in config mode"
    /// (given Netmiko's own comment equating tmsh with config), this
    /// forces that internal flag back to false explicitly — TMSH is a
    /// shell you're always in on this platform, not a transient
    /// config-mode state a generic isInConfigMode() check should ever
    /// report as true.
    ///
    /// The terminal-width trick is unusual too: rather than a normal
    /// CLI command, it shells out via "run /util bash -c" to invoke
    /// the real Unix "stty" utility directly, setting the terminal to
    /// 255 columns at the OS level rather than through any TMSH-level
    /// setting.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "#")
        _ = try await tmshMode()
        inConfigMode = false

        let widthCommand = #"run /util bash -c "stty cols 255""#
        try await setTerminalWidth(command: widthCommand, pattern: "run")

        try await disablePaging(
            command: "modify cli preference pager disabled display-threshold 0"
        )
    }

    // MARK: TMSH Mode

    /// Enter tmsh from the base Linux/bash prompt.
    ///
    /// Maps to netmiko's tmsh_mode(delay_factor=1.0).
    ///
    /// Sends a leading AND trailing return around the "tmsh" command
    /// itself — unusual compared to most command sends, which only
    /// terminate with a single trailing return. Waits for TMOS's
    /// distinctive prompt shape ("tmos...#") rather than a generic
    /// "#", then re-detects the base prompt since entering tmsh
    /// changes what that prompt looks like.
    ///
    /// Internal, not private — exposed so a caller who has dropped
    /// back to the base shell (e.g. after exitTmsh()) can re-enter
    /// tmsh manually if needed.
    @discardableResult
    internal func tmshMode(delay: TimeInterval = 1.0) async throws -> String {
        let command = profile.returnCharacter + "tmsh" + profile.returnCharacter
        let output = try await sendCommand(command, expectString: "tmos.*#")
        try await setBasePrompt()
        return output
    }

    /// Exit tmsh, returning to the base Linux/bash prompt.
    /// Maps to netmiko's exit_tmsh().
    @discardableResult
    internal func exitTmsh() async throws -> String {
        let output = try await sendCommand("quit", expectString: "#")
        try await setBasePrompt()
        return output
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="exit").
    ///
    /// Best-effort: exits tmsh first, swallowing any failure, then
    /// always sends the final exit command regardless — same
    /// best-effort shape as Juniper, Check Point Gaia, and Ericsson
    /// MiniLink's cleanup implementations.
    override public func cleanup(command: String = "exit") async throws {
        do {
            _ = try await exitTmsh()
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }
}
