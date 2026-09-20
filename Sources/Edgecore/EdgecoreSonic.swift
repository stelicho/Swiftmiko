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
// Sources/Swiftmiko/Edgecore/EdgecoreSonic.swift

import Foundation

/// Edgecore SONiC SSH driver.
///
/// Maps to netmiko's EdgecoreSonicSSH(LinuxSSH). Edgecore's SONiC
/// build needs no overrides of its own — every method comes straight
/// from LinuxSSHConnection.
public final class EdgecoreSonicSSH: LinuxSSHConnection {}
