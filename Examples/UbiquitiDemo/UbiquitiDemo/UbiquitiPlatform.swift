// Examples/UbiquitiDemo/UbiquitiPlatform.swift
import Foundation
import Combine

/// The Ubiquiti drivers in Sources/Ubiquiti/, mapped to their
/// registered device_type strings (see SSHDispatcher.swift).
///
/// "ubiquiti_edge" and "ubiquiti_edgeswitch" are aliases for the same
/// driver (UbiquitiEdgeSSH) — EdgeSwitch is the only hardware that
/// driver actually targets, "ubiquiti_edge" is just the older/shorter
/// netmiko-compatible name. This demo only exposes one of the two,
/// since picking between them wouldn't change any behavior.
enum UbiquitiPlatform: String, CaseIterable, Identifiable {
    case unifiSwitch = "ubiquiti_unifiswitch"
    case edgeSwitch = "ubiquiti_edgeswitch"
    case edgeRouter = "ubiquiti_edgerouter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unifiSwitch: return "UniFi Switch"
        case .edgeSwitch: return "EdgeSwitch"
        case .edgeRouter: return "EdgeRouter"
        }
    }

    /// UniFi Switch and EdgeSwitch both inherit UbiquitiEdgeSSH, which
    /// calls enterEnableMode() during session preparation — same
    /// Cisco-style privilege model.
    ///
    /// EdgeRouter inherits VyOSSSH instead, which has no enable-mode
    /// concept at all: you're at full privilege immediately after
    /// login, and changes go through "configure" / "commit" / "exit"
    /// rather than a separate privilege level. VyOSSSH doesn't
    /// override enterEnableMode() the way NoEnable drivers do, so
    /// calling it wouldn't throw — it would just send a Cisco-style
    /// "enable" command EdgeRouter doesn't recognize and likely hang
    /// waiting for a password prompt that's never coming. Treat it as
    /// unsupported here, the same way MultiVendorDemo treats Juniper
    /// and Fortinet.
    var supportsEnableMode: Bool {
        switch self {
        case .unifiSwitch, .edgeSwitch: return true
        case .edgeRouter: return false
        }
    }

    var commands: [CommonCommand] {
        switch self {
        case .unifiSwitch, .edgeSwitch:
            // Both run the same EdgeSwitch-style CLI (Cisco IOS-like
            // syntax) once past the UniFi-specific "telnet localhost"
            // session setup — see Sources/Ubiquiti/UnifiswitchSSH.swift.
            return [
                .init(label: "Version", command: "show version"),
                .init(label: "Running Config", command: "show running-config"),
                .init(label: "Interface Status", command: "show interfaces status"),
                .init(label: "VLANs", command: "show vlan"),
                .init(label: "MAC Address Table", command: "show mac-address-table"),
                .init(label: "PoE Status", command: "show poe status"),
            ]
        case .edgeRouter:
            // EdgeOS/VyOS syntax — no "running-config"/"vlan brief"
            // here, config is viewed and committed differently.
            return [
                .init(label: "Version", command: "show version"),
                .init(label: "Configuration", command: "show configuration commands"),
                .init(label: "Interfaces", command: "show interfaces"),
                .init(label: "IP Route Table", command: "show ip route"),
                .init(label: "DHCP Leases", command: "show dhcp leases"),
                .init(label: "System Uptime", command: "show system uptime"),
            ]
        }
    }
}

struct CommonCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String
}
