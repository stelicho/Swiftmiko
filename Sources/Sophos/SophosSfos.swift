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
// Sources/Swiftmiko/Sophos/SophosSfos.swift

import Foundation

/// Default Sophos SFOS console menu option, configurable via the
/// SWIFTMIKO_SOPHOS_MENU environment variable (renamed from Netmiko's
/// own env var below).
///
/// Maps to netmiko's module-level:
///     SOPHOS_MENU_DEFAULT = os.getenv("NETMIKO_SOPHOS_MENU", "4")
///
/// Note: this constant is defined in the Python source but is not
/// actually referenced anywhere in SophosSfosSSH itself — it appears
/// unused in this file. Carried over here for parity and in case a
/// caller or a future menu-navigation helper needs it, but flagged
/// as dead code as translated. Worth confirming against a newer
/// Netmiko release whether this is genuinely unused or wired up
/// elsewhere (e.g. a helper method not present in this file).
public let sophosMenuDefault: String = {
    ProcessInfo.processInfo.environment["SWIFTMIKO_SOPHOS_MENU"] ?? "4"
}()

/// Sophos SFOS (XG Firewall) SSH driver.
///
/// Maps to netmiko's SophosSfosSSH(NoEnable, NoConfig, CiscoSSHConnection).
///
/// Sophos SFOS does not present a normal CLI prompt over SSH at all —
/// it drops you into a numbered console menu:
///
///     Sophos Firmware Version SFOS 18.0.0 GA-Build339
///
///     Main Menu
///
///         1.  Network  Configuration
///         2.  System   Configuration
///         3.  Route    Configuration
///         4.  Device Console
///         5.  Device Management
///         6.  VPN Management
///         7.  Shutdown/Reboot Device
///         0.  Exit
///
///         Select Menu Number [0-7]:
///
/// There is no enable step and no configuration mode in the
/// traditional sense — hence NoEnable + NoConfig. session_preparation
/// only confirms the menu appeared and redisplays it; navigating to
/// option 4 (Device Console) for a real shell is left to the caller.
public final class SophosSfosSSH: CiscoSSHConnection, NoEnable, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"Select Menu Number")
    ///     self.send_command_expect("\r", expect_string=r"Select Menu Number")
    ///     time.sleep(0.3 * self.global_delay_factor)
    ///     self.clear_buffer()
    ///
    /// The second step re-sends a bare carriage return and waits for
    /// the menu prompt again — this just confirms the menu is stable
    /// and ready for input, it does not select any option.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "Select Menu Number")
        _ = try await sendCommand(
            "\r",
            expectString: "Select Menu Number",
            stripPrompt: false,
            stripCommand: false
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        try await clearBuffer()
    }

    // MARK: Save Config

    /// Not supported — there is no config mode to save from.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Sophos SFOS does not support saveConfig()"
        )
    }
}
