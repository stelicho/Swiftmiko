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
// Sources/Swiftmiko/Opengear/OpengearLinux.swift

import Foundation

/// Opengear (console server / out-of-band management) SSH driver.
///
/// Maps to netmiko's OpengearLinuxSSH(LinuxSSH). Needs no overrides
/// of its own — every method comes straight from LinuxSSHConnection.
public final class OpengearLinuxSSH: LinuxSSHConnection {}
