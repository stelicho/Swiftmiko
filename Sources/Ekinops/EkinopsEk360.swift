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
// Sources/Swiftmiko/Ekinops/EkinopsEk360.swift

import Foundation

/// Ekinops EK-360 SSH driver.
///
/// Maps to netmiko's EkinopsEk360SSH(OneaccessOneOSBase).
///
/// IMPORTANT: this inherits from a class in a DIFFERENT vendor's
/// module — OneaccessOneOSBase, from netmiko.oneaccess — not from
/// anything in the Ekinops family itself. This is a genuine
/// cross-vendor rebrand relationship, similar in spirit to Cisco
/// APIC inheriting from LinuxSSH, except here it's two distinct
/// named hardware vendors rather than a generic OS layer. Ekinops'
/// EK-360 optical transport platform is apparently a rebadged or
/// OEM'd OneAccess device under the hood, sharing its CLI entirely.
///
/// This file cannot be meaningfully completed until OneaccessOneOSBase
/// itself has been translated — everything this driver does comes
/// from that base class, and none of it is visible from this file
/// alone. Placeholder below assumes the eventual Swift name follows
/// the established `<Vendor><Product>Base` convention; update the
/// inheritance once that file exists.
public final class EkinopsEk360SSH: OneaccessOneOSBase {}
