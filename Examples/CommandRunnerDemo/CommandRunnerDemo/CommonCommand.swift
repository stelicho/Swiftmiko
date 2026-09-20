// Examples/CommandRunnerDemo/CommonCommand.swift
import Foundation

/// A curated set of common Cisco IOS/IOS-XE show commands, grouped
/// loosely by category for the picker.
struct CommonCommand: Identifiable, Hashable {
    let id = UUID()
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
