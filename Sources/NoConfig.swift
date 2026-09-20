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
//  NoConfig.swift
//  Swiftmiko
//
//  Port of netmiko/no_config.py
//

public protocol NoConfig: AnyObject {}

/// Helpers for drivers that do not have a configuration mode.
public enum NoConfigBehavior {
    public static func enter() throws {
        throw SwiftmikoError.configModeNotSupported
    }

    public static func exit() {}
}

