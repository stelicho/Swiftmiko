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

    // NoConfig: real Netmiko's mixin is a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->""),
    // not a throw — see Sources/NoConfig.swift for why this needs a
    // direct override rather than a protocol extension default.
    override public func isInConfigMode(checkString: String = "", pattern: String = "") async throws -> Bool {
        NoConfigBehavior.isInConfigMode()
    }

    @discardableResult
    override public func enterConfigMode(command: String = "", pattern: String = "", dotAll: Bool = false) async throws -> String {
        NoConfigBehavior.enter()
    }

    @discardableResult
    override public func exitConfigMode(exitConfig: String = "exit", pattern: String = "") async throws -> String {
        NoConfigBehavior.exit()
    }

    // NoEnable: same trivial-pass-through story — see Sources/NoEnable.swift.
    override public func isInEnableMode(checkString: String = "") async throws -> Bool {
        NoEnableBehavior.isInEnableMode()
    }

    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "",
        pattern: String = "",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        NoEnableBehavior.enter()
    }

    @discardableResult
    override public func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        NoEnableBehavior.exit()
    }

    /// JuniperScreenOsSSH extends BaseConnection directly, whose
    /// disablePaging() unconditionally throws — this gives it the same
    /// real generic behavior CiscoBaseConnection-rooted drivers get.
    /// sessionPreparation() always passes its own explicit command, so
    /// this override's own default is never actually relied upon.
    @discardableResult
    override public func disablePaging(
        command: String = "set console page 0",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await genericDisablePaging(command: command)
    }

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
