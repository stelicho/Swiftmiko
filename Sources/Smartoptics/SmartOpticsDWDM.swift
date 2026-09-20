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
