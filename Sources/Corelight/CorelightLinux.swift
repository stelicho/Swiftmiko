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
// Sources/Swiftmiko/Corelight/CorelightLinux.swift

import Foundation

/// Corelight (network security sensor appliance) SSH driver.
///
/// Maps to netmiko's CorelightLinuxSSH(LinuxSSH). Corelight's
/// underlying OS is close enough to a standard Linux SSH session that
/// it needs no overrides of its own — every method (session prep,
/// prompt detection, paging) comes straight from LinuxSSHConnection.
public final class CorelightLinuxSSH: LinuxSSHConnection {}
