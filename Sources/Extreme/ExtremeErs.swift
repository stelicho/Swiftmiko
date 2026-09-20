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
// Sources/Swiftmiko/Extreme/ExtremeErs.swift

import Foundation

/// Raw control characters used during Extreme ERS's login sequence.
/// Maps to netmiko's module-level CTRL_Y / CTRL_C constants.
private enum ExtremeControlCharacter {
    /// Ctrl-Y (ASCII 25) — begins the login process on ERS devices.
    static let ctrlY = "\u{19}"
    /// Ctrl-C (ASCII 3) — Python's chr(0x63) is actually lowercase
    /// 'c' (ASCII 99), NOT Ctrl-C (ASCII 3). This looks like a bug in
    /// Netmiko's own source: CTRL_C = "\x63" decodes to the literal
    /// character 'c', not a control character at all. Preserved
    /// EXACTLY as written in Python — sending the literal letter "c"
    /// — rather than "fixing" it to a real Ctrl-C (\x03), since
    /// correcting this without testing against a real device could
    /// break behavior that happens to work today (perhaps the "Menu"
    /// prompt genuinely expects the letter 'c' as a menu selection,
    /// not a control sequence, despite the misleading constant name).
    static let ctrlC = "\u{63}"
}

/// Extreme Ethernet Routing Switch (ERS) SSH driver.
///
/// Maps to netmiko's ExtremeErsSSH(CiscoSSHConnection).
///
/// IMPORTANT: ExtremeVspSSH inherits from this class specifically to
/// reuse specialLoginHandler() — Netmiko's own docstring warns
/// against adding extra methods here without checking for negative
/// side effects on VSP. That warning is preserved and should be
/// respected in any future changes to this file.
open class ExtremeErsSSH: CiscoSSHConnection {

    override public nonisolated var promptPattern: String {
        #"(?m:[>#]\s*$)"#
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — deliberately minimal,
    /// since specialLoginHandler() already guarantees the session has
    /// reached promptPattern before this ever runs.
    override public func sessionPreparation() async throws {
        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
    }

    // MARK: Login Handling

    /// Handle Extreme ERS's variable login sequence.
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// ERS devices present a genuinely inconsistent login flow across
    /// firmware generations, per Netmiko's own comments: older
    /// devices may show "Enter Ctrl-Y to begin" before SSH
    /// authentication even completes; some devices go to a blank
    /// screen after Ctrl-Y requiring a bare Return to proceed; newer
    /// devices show the Ctrl-Y prompt AFTER SSH login instead. This
    /// loop tolerates all of these by treating five different signals
    /// (username prompt, password prompt, "Ctrl-Y", "Press ENTER",
    /// or a menu banner) as valid next steps, in any order, until the
    /// real device prompt finally appears.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        var output = ""
        let usernameLabel = "sername"
        let passwordLabel = "ssword"
        let ctrlYLabel = "Ctrl-Y"
        let enterLabel = "Press ENTER to continue"
        let combinedPattern = "(?:\(usernameLabel)|\(passwordLabel)|\(ctrlYLabel)|\(enterLabel)|\(promptPattern)|Menu)"

        while true {
            let newData = try await readUntilPattern(pattern: combinedPattern, timeout: 25.0)
            output += newData

            if newData.range(of: promptPattern, options: .regularExpression) != nil {
                return
            }

            if newData.contains(ctrlYLabel) {
                try await writeChannel(ExtremeControlCharacter.ctrlY)
                try await Task.sleep(nanoseconds: UInt64(1.0 * delay * 1_000_000_000))
                // No pattern to wait for here — some devices go blank
                // after Ctrl-Y until a bare Return is sent.
                try await writeChannel(profile.returnCharacter)
            } else if newData.contains("Press ENTER") {
                try await writeChannel(profile.returnCharacter)
            } else if newData.contains(usernameLabel) {
                try await writeChannel(profile.username + profile.returnCharacter)
            } else if newData.contains(passwordLabel) {
                guard case .password(let password) = profile.auth else {
                    throw SwiftmikoError.authenticationFailed(
                        "Extreme ERS requires password authentication"
                    )
                }
                try await writeChannel(password + profile.returnCharacter)
            } else if newData.contains("Menu") {
                try await writeChannel(ExtremeControlCharacter.ctrlC)
            } else {
                throw SwiftmikoError.authenticationFailed(
                    """


                    Failed to login to Extreme ERS Device.

                    Pattern not detected: \(combinedPattern)
                    output:

                    \(output)

                    """
                )
            }
        }
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save config").
    override public func saveConfig(
        command: String = "save config",
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

// MARK: - ExtremeVspSSH

/// Extreme Virtual Services Platform (VSP) SSH driver.
///
/// Maps to netmiko's ExtremeVspSSH(ExtremeErsSSH).
///
/// Inherits from ExtremeErsSSH specifically to reuse its Ctrl-Y
/// specialLoginHandler() — VSP shares the same quirky login banner
/// behavior as ERS despite otherwise being a distinct product line
/// with its own session-prep and paging command.
public final class ExtremeVspSSH: ExtremeErsSSH {

    /// Maps to netmiko's session_preparation() — fully replaces the
    /// parent's version (which is itself minimal) with VSP's own
    /// prompt-test pattern and paging command.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "terminal more disable")
    }

    /// Maps to netmiko's save_config(cmd="save config") — identical
    /// defaults to the parent's own saveConfig(), but re-declared
    /// here explicitly for clarity/parity with the Python source,
    /// which redeclares it too despite it being unchanged.
    override public func saveConfig(
        command: String = "save config",
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
