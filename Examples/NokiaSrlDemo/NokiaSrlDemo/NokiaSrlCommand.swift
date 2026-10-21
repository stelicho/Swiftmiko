// Examples/NokiaSrlDemo/NokiaSrlCommand.swift
import Foundation

/// A curated set of common Nokia SR Linux classic-CLI show commands,
/// for the picker. SR Linux's command vocabulary is quite different
/// from Cisco's — network-instance-scoped rather than global.
struct NokiaSrlCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [NokiaSrlCommand] = [
        .init(label: "Version", command: "show version"),
        .init(label: "System Information", command: "show system information"),
        .init(label: "Interfaces (brief)", command: "show network-instance default interfaces brief"),
        .init(label: "Platform / Chassis", command: "show platform"),
        .init(label: "ARP Table", command: "show network-instance default arp"),
        .init(label: "BGP Neighbors", command: "show network-instance default protocols bgp neighbor"),
    ]
}
