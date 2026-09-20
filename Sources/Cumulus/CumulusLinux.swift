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
// Sources/Swiftmiko/Cumulus/CumulusLinux.swift

import Foundation

/// Cumulus Linux SSH driver.
///
/// Maps to netmiko's CumulusLinuxSSH(LinuxSSH).
///
/// Otherwise identical to a standard Linux SSH session — only
/// saveConfig() is overridden, using Cumulus's NVUE-style "nv config
/// apply" command rather than a traditional "write"/"save" style
/// command.
public final class CumulusLinuxSSH: LinuxSSHConnection {

    /// Apply the staged NVUE configuration.
    ///
    /// Maps to netmiko's save_config(cmd="nv config apply").
    ///
    /// Note the commented-out `# self.enable()` line in the Python
    /// source — left disabled there, presumably because Cumulus's
    /// "nv config apply" doesn't require privilege escalation (or
    /// LinuxSSH's enable() wouldn't make sense to call at all, given
    /// LinuxSSH devices typically have no real enable-mode concept).
    /// Preserved here as an intentional omission rather than an
    /// oversight — worth confirming during testing whether a real
    /// device ever needs it, but nothing in this file suggests
    /// enabling it is necessary.
    override public func saveConfig(
        command: String = "nv config apply",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(
            command,
            readTimeout: 100.0,
            stripPrompt: false,
            stripCommand: false
        )
    }
}
