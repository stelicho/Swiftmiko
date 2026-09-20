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
// Sources/Swiftmiko/Moxa/MoxaNos.swift

import Foundation

/// MOXA NOS SSH driver base.
///
/// Tested with EDS-508A and EDS-516A, per Netmiko's own module
/// docstring.
///
/// Note: this only works in CLI mode. If the device is in Menu mode,
/// that needs to be changed first — Swiftmiko has no way to detect
/// or switch modes for this device automatically, since Netmiko's
/// own driver provides no overrides to handle that case either.
///
/// Maps to netmiko's MoxaNosBase(CiscoSSHConnection). No overrides at
/// all — relies entirely on CiscoSSHConnection's own defaults.
public class MoxaNosBase: CiscoSSHConnection {}

// MARK: - MoxaNosSSH

/// MOXA NOS SSH driver — no differences from the base.
/// Maps to netmiko's MoxaNosSSH(MoxaNosBase).
public final class MoxaNosSSH: MoxaNosBase {}
