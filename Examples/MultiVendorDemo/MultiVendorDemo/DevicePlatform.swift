// Examples/MultiVendorDemo/DevicePlatform.swift
import Foundation
import Combine

/// Supported demo platforms, mapping to Swiftmiko's registered
/// device_type strings and each platform's own command vocabulary.
enum DevicePlatform: String, CaseIterable, Identifiable {
    case ciscoIOS = "cisco_ios"
    case aristaEOS = "arista_eos"
    case juniperJunOS = "juniper_junos"
    case fortinet = "fortinet"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ciscoIOS: return "Cisco IOS / IOS-XE"
        case .aristaEOS: return "Arista EOS"
        case .juniperJunOS: return "Juniper JunOS"
        case .fortinet: return "Fortinet FortiGate"
        }
    }

    /// Juniper and Fortinet drivers conform to NoEnable — there is no
    /// privilege-escalation step to run at all on those platforms.
    var supportsEnableMode: Bool {
        switch self {
        case .ciscoIOS, .aristaEOS: return true
        case .juniperJunOS, .fortinet: return false
        }
    }

    var commands: [CommonCommand] {
        switch self {
        case .ciscoIOS:
            return [
                .init(label: "Version", command: "show version"),
                .init(label: "Running Config", command: "show running-config"),
                .init(label: "Interfaces (brief)", command: "show ip interface brief"),
                .init(label: "VLANs", command: "show vlan brief"),
                .init(label: "MAC Address Table", command: "show mac address-table"),
                .init(label: "CDP Neighbors", command: "show cdp neighbors"),
            ]
        case .aristaEOS:
            return [
                .init(label: "Version", command: "show version"),
                .init(label: "Running Config", command: "show running-config"),
                .init(label: "Interfaces (brief)", command: "show ip interface brief"),
                .init(label: "VLANs", command: "show vlan"),
                .init(label: "MAC Address Table", command: "show mac address-table"),
                .init(label: "LLDP Neighbors", command: "show lldp neighbors"),
            ]
        case .juniperJunOS:
            return [
                .init(label: "Version", command: "show version"),
                .init(label: "Configuration", command: "show configuration"),
                .init(label: "Interfaces (terse)", command: "show interfaces terse"),
                .init(label: "Routing Table", command: "show route"),
                .init(label: "ARP Table", command: "show arp"),
                .init(label: "Chassis Hardware", command: "show chassis hardware"),
            ]
        case .fortinet:
            return [
                .init(label: "System Status", command: "get system status"),
                .init(label: "Interfaces", command: "get system interface physical"),
                .init(label: "Routing Table", command: "get router info routing-table all"),
                .init(label: "Firewall Policies", command: "show firewall policy"),
                .init(label: "Sessions", command: "get system session list"),
                .init(label: "HA Status", command: "get system ha status"),
            ]
        }
    }
}

struct CommonCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String
}
