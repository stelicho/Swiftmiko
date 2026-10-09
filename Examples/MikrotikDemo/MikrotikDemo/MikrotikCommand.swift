// Examples/MikrotikDemo/MikrotikCommand.swift
import Foundation

/// A curated set of RouterOS CLI commands — note the leading "/", part
/// of RouterOS's own menu-path command syntax rather than a Cisco-style
/// bare keyword.
struct MikrotikCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [MikrotikCommand] = [
        .init(label: "Identity / Version", command: "/system resource print"),
        .init(label: "RouterBoard Info", command: "/system routerboard print"),
        .init(label: "Interfaces", command: "/interface print"),
        .init(label: "IP Addresses", command: "/ip address print"),
        .init(label: "Routes", command: "/ip route print"),
        .init(label: "DHCP Leases", command: "/ip dhcp-server lease print"),
    ]
}
