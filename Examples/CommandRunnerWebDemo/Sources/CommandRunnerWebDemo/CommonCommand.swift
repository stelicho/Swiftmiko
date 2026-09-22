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
//  Examples/CommandRunnerWebDemo/CommonCommand.swift
//
//  Same curated command library as the SwiftUI CommandRunnerDemo,
//  duplicated here rather than shared — these are two independent
//  Xcode/SwiftPM projects, not two targets in one package.

struct CommonCommand {
    let label: String
    let command: String

    static let library: [CommonCommand] = [
        .init(label: "Version", command: "show version"),
        .init(label: "Running Config", command: "show running-config"),
        .init(label: "Interfaces (brief)", command: "show ip interface brief"),
        .init(label: "VLANs", command: "show vlan brief"),
        .init(label: "MAC Address Table", command: "show mac address-table"),
        .init(label: "ARP Table", command: "show arp"),
        .init(label: "Routing Table", command: "show ip route"),
        .init(label: "CDP Neighbors", command: "show cdp neighbors"),
        .init(label: "Spanning Tree", command: "show spanning-tree"),
        .init(label: "Interface Status", command: "show interfaces status"),
        .init(label: "CPU Utilization", command: "show processes cpu"),
        .init(label: "Uptime & Inventory", command: "show inventory"),
    ]
}
