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
// Sources/Swiftmiko/F5/F5Linux.swift

import Foundation

/// F5 BIG-IP Linux (underlying host OS) SSH driver.
///
/// Maps to netmiko's F5LinuxSSH(LinuxSSH). Needs no overrides of its
/// own — every method comes straight from LinuxSSHConnection.
public final class F5LinuxSSH: LinuxSSHConnection {}
