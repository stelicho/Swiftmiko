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
// Sources/Swiftmiko/Enterasys/Enterasys.swift

import Foundation

/// Enterasys SSH driver.
///
/// Maps to netmiko's EnterasysSSH(CiscoSSHConnection).
public final class EnterasysSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r">")
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="set length 0")
    ///
    /// Netmiko's docstring claims "Enterasys requires enable mode to
    /// disable paging," but no call to enable() actually appears
    /// anywhere in this method. Preserved exactly as written rather
    /// than "corrected" by adding an enterEnableMode() call that
    /// isn't in the source — this may be a stale comment left over
    /// from an earlier version of the driver, or the device may
    /// simply not need it in practice despite the comment. Worth
    /// confirming against a real device before assuming either
    /// explanation.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: ">")
        try await setBasePrompt()
        try await disablePaging(command: "set length 0")
    }

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Enterasys does not support saveConfig()"
        )
    }
}
