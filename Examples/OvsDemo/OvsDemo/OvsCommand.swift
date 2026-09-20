// Examples/OvsDemo/OvsCommand.swift
import Foundation
import Swiftmiko

/// A curated set of common OVS commands, requiring root (via sudo).
struct OvsCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [OvsCommand] = [
        .init(label: "Show Topology", command: "ovs-vsctl show"),
        .init(label: "List Bridges", command: "ovs-vsctl list-br"),
        .init(label: "List All Ports", command: "ovs-vsctl list-ports"),
        .init(label: "OVS Version", command: "ovs-vsctl --version"),
        .init(label: "Dump Flows (br0)", command: "ovs-ofctl dump-flows br0"),
        .init(label: "Port Statistics (br0)", command: "ovs-ofctl dump-ports br0"),
        .init(label: "OpenFlow Version", command: "ovs-ofctl show br0"),
        .init(label: "Fail Mode", command: "ovs-vsctl get-fail-mode br0"),
    ]
}
