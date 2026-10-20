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
/// module — OneaccessOneOSBase, from Sources/Oneaccess/OneaccessOneos.swift
/// — not from anything in the Ekinops family itself. This is a genuine
/// cross-vendor rebrand relationship, similar in spirit to Cisco
/// APIC inheriting from LinuxSSH, except here it's two distinct
/// named hardware vendors rather than a generic OS layer. Ekinops'
/// EK-360 optical transport platform is apparently a rebadged or
/// OEM'd OneAccess device under the hood, sharing its CLI entirely.
/// Matches real Netmiko's own equally trivial pass-through subclass.
public final class EkinopsEk360SSH: OneaccessOneOSBase {}
