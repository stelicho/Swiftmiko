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
// Sources/Swiftmiko/Juniper/JuniperScreenOs.swift

import Foundation

/// Juniper ScreenOS SSH driver (the older NetScreen-derived firewall
/// OS, distinct from modern JunOS).
///
/// Maps to netmiko's JuniperScreenOsSSH(NoEnable, NoConfig,
/// BaseConnection).
///
/// No privilege escalation and no configuration mode via this
/// connection type — hence NoEnable + NoConfig. ScreenOS can be
/// configured to require an interactive license/terms acceptance
/// prompt before allowing login to proceed.
public final class JuniperScreenOsSSH: BaseConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Handle ScreenOS's optional terms-acceptance prompt, then
    /// prepare the session normally.
    ///
    /// Maps to netmiko's session_preparation():
    ///     terminator = r"\->"
    ///     pattern = rf"(?:Accept this.*|{terminator})"
    ///     data = self.read_until_pattern(pattern=pattern)
    ///     if "Accept this" in data:
    ///         self.write_channel("y")
    ///         data += self.read_until_pattern(pattern=terminator)
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="set console page 0")
    ///
    /// ScreenOS's prompt terminator is a literal "->" arrow rather
    /// than the more typical single ">"/"#" character.
    override public func sessionPreparation() async throws {
        let terminator = #"\->"#
        let pattern = "(?:Accept this.*|\(terminator))"

        var data = try await readUntilPattern(pattern: pattern)
        if data.contains("Accept this") {
            try await writeChannel("y")
            data += try await readUntilPattern(pattern: terminator)
        }

        try await setBasePrompt()
        try await disablePaging(command: "set console page 0")
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="save config").
    ///
    /// Note this bypasses the base implementation entirely and sends
    /// the command directly — Netmiko's own version doesn't call
    /// super().save_config() here the way most drivers do, presumably
    /// because ScreenOS's save doesn't need any of the confirm/
    /// confirmResponse handling the base save_config machinery
    /// provides.
    public func saveConfig(
        command: String = "save config",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(command)
    }
}
