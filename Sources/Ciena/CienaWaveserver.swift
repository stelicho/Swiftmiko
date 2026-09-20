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
// Sources/Swiftmiko/Ciena/CienaWaveserver.swift

import Foundation

/// Ciena Waveserver SSH driver — no differences from the base.
///
/// Maps to netmiko's CienaWaveserverSSH(CienaSaosBase).
///
/// Waveserver is Ciena's optical transport platform; apparently its
/// CLI is close enough to standard SAOS that it needs no overrides of
/// its own at all — every method (prompt detection, session prep,
/// shell access, save config) comes straight from CienaSaosBase.
public final class CienaWaveserverSSH: CienaSaosBase {}
