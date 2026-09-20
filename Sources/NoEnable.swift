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
//  NoEnable.swift
//  Swiftmiko
//
//  Port of netmiko/no_enable.py
//

public protocol NoEnable: AnyObject {}

public enum NoEnableBehavior {
    public static func enter() {}
    public static func isEnabled() -> Bool { true }
}

public extension NoEnable where Self: BaseConnection {
    func enterEnableMode(secret: String) async throws {
        _ = secret
        NoEnableBehavior.enter()
    }

    func isInEnableMode() async throws -> Bool {
        NoEnableBehavior.isEnabled()
    }
}
