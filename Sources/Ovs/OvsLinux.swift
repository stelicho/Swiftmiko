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
// Sources/Swiftmiko/Ovs/OvsLinux.swift

import Foundation

/// Open vSwitch (OVS) Linux SSH driver.
///
/// Maps to netmiko's OvsLinuxSSH(LinuxSSH). Needs no overrides of its
/// own — every method comes straight from LinuxSSHConnection.
public final class OvsLinuxSSH: LinuxSSHConnection {}
