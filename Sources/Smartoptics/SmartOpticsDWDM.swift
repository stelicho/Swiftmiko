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
// Sources/Swiftmiko/SmartOptics/SmartOpticsDWDM.swift

import Foundation

/// SmartOptics DWDM SSH driver.
///
/// Maps to netmiko's SmartOpticsDWDMSSH(BaseConnection).
///
/// The most minimal driver in the vendor set — inherits everything
/// from BaseConnection directly (no Cisco-family base, no mixins) and
/// overrides only prompt terminator detection. There is no custom
/// session_preparation, meaning this class relies entirely on
/// BaseConnection's default sessionPreparation(), which calls
/// disablePaging() and will throw notImplemented unless the base's
/// default paging behavior has since been made a safe no-op rather
/// than a hard failure — worth verifying against a real device before
/// trusting this driver to connect cleanly out of the box.
public final class SmartOpticsDWDMSSH: BaseConnection {

    /// Real Netmiko has no explicit disablePaging() or
    /// sessionPreparation() override for this driver either — it
    /// relies ENTIRELY on BaseConnection's own default
    /// session_preparation() and disable_paging(), which in real
    /// Netmiko is a genuine, working generic implementation (write
    /// "terminal length 0", read the echo, read until prompt) rather
    /// than a throw. Swiftmiko's BaseConnection.disablePaging()
    /// deliberately throws by default instead (an ambiguous device
    /// hasn't decided how to disable paging), so this override exists
    /// purely to restore the real generic behavior this driver was
    /// always meant to inherit.
    @discardableResult
    override public func disablePaging(
        command: String = "terminal length 0",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await genericDisablePaging(command: command)
    }

    /// Maps to netmiko's set_base_prompt(), forwarded to the base
    /// implementation with no behavioral change — this override
    /// exists in the Python source only to make the terminator
    /// defaults explicit for this device, not to alter any logic.
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
    }
}
