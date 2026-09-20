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
//  TelnetLib.swift
//  Swiftmiko
//
//  The concrete Telnet transport is NIOTelnetChannel (Sources/NIOTelnetChannel.swift).
//  It conforms to Channel and TelnetNegotiatingChannel and is wired in automatically
//  by SSHDispatcher for all device types ending in "_telnet".
//
//  Protocol scaffolding (TelnetSocket, TelnetNegotiatingChannel, TelnetOption)
//  lives in TelnetProxy.swift.
//

