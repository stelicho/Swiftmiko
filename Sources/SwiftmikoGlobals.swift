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
//
//  SwiftmikoGlobals.swift
//  Swiftmiko
//
//  Port of netmiko_globals.py
//

import Foundation

/// Maximum channel buffer size used by Swiftmiko read loops.
public let swiftmikoMaxBuffer = 65_535

/// Backspace emitted by several network-device CLIs.
public let swiftmikoBackspaceCharacter = "\u{08}"

// Compatibility spellings matching Netmiko's module constants.
public let MAX_BUFFER = swiftmikoMaxBuffer
public let BACKSPACE_CHAR = swiftmikoBackspaceCharacter
