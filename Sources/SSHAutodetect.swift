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
//  SSHAutodetect.swift
//  Swiftmiko
//
//  Port of netmiko/ssh_autodetect.py
//

import Foundation

public enum SSHAutodetectStrategy: Sendable {
    case standard
    case loginBanner
    case remoteVersion
}

public struct SSHAutodetectRule: Sendable {
    public let command: String
    public let searchPatterns: [String]
    public let priority: Int
    public let strategy: SSHAutodetectStrategy

    public init(
        command: String,
        searchPatterns: [String],
        priority: Int = 99,
        strategy: SSHAutodetectStrategy = .standard
    ) {
        self.command = command
        self.searchPatterns = searchPatterns
        self.priority = priority
        self.strategy = strategy
    }
}

/// Device signatures used by SSH autodetection.
///
/// The command ordering is calculated from command frequency, matching
/// Netmiko's `SSH_MAPPER_BASE`: commands shared by more device types run first
/// so their output can be cached and reused.
public enum SSHAutodetectMapper {
    public static let rules: [String: SSHAutodetectRule] = [
        "alcatel_aos": .init(command: "show system", searchPatterns: ["Alcatel-Lucent"]),
        "alcatel_sros": .init(command: "show version", searchPatterns: ["Nokia", "Alcatel"]),
        "allied_telesis_awplus": .init(command: "show version", searchPatterns: ["AlliedWare Plus"]),
        "apresia_aeos": .init(command: "show system", searchPatterns: ["Apresia"]),
        "arista_eos": .init(command: "show version", searchPatterns: ["Arista", "vEOS"]),
        "aruba_aoscx": .init(command: "show version", searchPatterns: ["ArubaOS-CX", "AOS-CX"]),
        "ciena_saos": .init(command: "software show", searchPatterns: ["saos"]),
        "ciena_waveserver": .init(command: "software show", searchPatterns: ["WAVESERVER"]),
        "cisco_ap": .init(command: "show version", searchPatterns: ["Cisco AP Software"]),
        "cisco_asa": .init(command: "show version", searchPatterns: ["Cisco Adaptive Security Appliance", "Cisco ASA"]),
        "cisco_ftd": .init(command: "show version", searchPatterns: ["Cisco Firepower"]),
        "cisco_ios": .init(command: "show version", searchPatterns: ["Cisco IOS Software", "Cisco Internetwork Operating System Software"], priority: 95),
        "cisco_xe": .init(command: "show version", searchPatterns: ["Cisco IOS XE Software"]),
        "cisco_nxos": .init(command: "show version", searchPatterns: ["Cisco Nexus Operating System", "NX-OS"]),
        "cisco_xr": .init(command: "show version", searchPatterns: ["Cisco IOS XR"]),
        "cisco_xr_2": .init(command: "show version brief", searchPatterns: ["Cisco IOS XR"]),
        "cumulus_linux": .init(command: "uname -a", searchPatterns: ["Linux cumulus"]),
        "dell_force10": .init(command: "show version", searchPatterns: ["Real Time Operating System Software"]),
        "dell_os9": .init(command: "show system", searchPatterns: ["Dell Application Software Version\\s*:\\s*9", "Dell Networking OS Version\\s*:\\s*9", "Dell EMC Networking OS Version\\s*:\\s*9"]),
        "dell_os10": .init(command: "show version", searchPatterns: ["Dell EMC Networking OS10.Enterprise", "Dell SmartFabric OS10[\\s*|-]Enterprise"]),
        "dell_powerconnect": .init(command: "show system", searchPatterns: ["PowerConnect"]),
        "f5_tmsh": .init(command: "show sys version", searchPatterns: ["BIG-IP"]),
        "f5_linux": .init(command: "cat /etc/issue", searchPatterns: ["BIG-IP"]),
        "h3c_comware": .init(command: "display version", searchPatterns: ["H3C Comware Software"]),
        "hirschmann_hios": .init(command: "", searchPatterns: ["Release HiOS-"], strategy: .loginBanner),
        "hp_comware": .init(command: "display version", searchPatterns: ["HPE Comware", "HP Comware"]),
        "hp_procurve": .init(command: "show version", searchPatterns: ["Image stamp.*/code/build"]),
        "huawei": .init(command: "display version", searchPatterns: ["Huawei Technologies", "Huawei Versatile Routing Platform Software"]),
        "juniper_junos": .init(command: "show version", searchPatterns: ["JUNOS Software Release", "JUNOS .+ Software", "JUNOS OS Kernel", "JUNOS Base Version"]),
        "linux": .init(command: "uname -a", searchPatterns: ["Linux"], priority: 95),
        "ericsson_ipos": .init(command: "show version", searchPatterns: ["Ericsson IPOS Version"]),
        "extreme_exos": .init(command: "show version", searchPatterns: ["ExtremeXOS", "EXOS"]),
        "extreme_netiron": .init(command: "show version", searchPatterns: ["(NetIron|MLX)"]),
        "extreme_slx": .init(command: "show version", searchPatterns: ["SLX-OS Operating System"]),
        "extreme_tierra": .init(command: "show version", searchPatterns: ["TierraOS Software"]),
        "ubiquiti_edgeswitch": .init(command: "show version", searchPatterns: ["EdgeSwitch"]),
        "cisco_wlc": .init(command: "", searchPatterns: ["CISCO_WLC"], strategy: .remoteVersion),
        "cisco_wlc_85": .init(command: "show inventory", searchPatterns: ["Cisco.*Wireless.*Controller"]),
        "mellanox_mlnxos": .init(command: "show version", searchPatterns: ["Onyx", "SX_PPC_M460EX"]),
        "yamaha": .init(command: "show copyright", searchPatterns: ["Yamaha Corporation"]),
        "fortinet": .init(command: "get system status", searchPatterns: ["FortiOS", "FortiGate"]),
        "paloalto_panos": .init(command: "show system info", searchPatterns: ["model:\\s+PA"]),
        "supermicro_smis": .init(command: "show system info", searchPatterns: ["Super Micro Computer"]),
        "flexvnf": .init(command: "show system package-info", searchPatterns: ["Versa FlexVNF"]),
        "cisco_viptela": .init(command: "show system status", searchPatterns: ["Viptela, Inc"]),
        "oneaccess_oneos": .init(command: "show version", searchPatterns: ["OneOS"]),
        "netgear_prosafe": .init(command: "show version", searchPatterns: ["ProSAFE"]),
        "moxa_nos": .init(command: "", searchPatterns: ["[Mm]oxa"], strategy: .remoteVersion),
        "huawei_smartax": .init(command: "display version", searchPatterns: ["Huawei Integrated Access Software"]),
        "nec_ix": .init(command: "show hardware", searchPatterns: ["IX Series"]),
        "fiberstore_fsosv2": .init(command: "show version", searchPatterns: ["Fiberstore Co., Limited Internetwork Operating System Software[\\s\\S]*Version 2.[0-9]*.[0-9]*[\\s\\S]*"]),
        "telcosystems_binos": .init(command: "show version", searchPatterns: ["BiNOS"])
    ]

    public static let orderedRules: [(String, SSHAutodetectRule)] = {
        var counts: [String: Int] = [:]
        for rule in rules.values {
            counts[rule.command, default: 0] += 1
        }
        return rules.sorted {
            counts[$0.value.command, default: 0] >
                counts[$1.value.command, default: 0]
        }
    }()
}

/// Attempts to identify a network device from SSH output and signatures.
public class SSHDetect {
    public let connection: BaseConnection
    public let initialBuffer: String
    public private(set) var potentialMatches: [String: Int] = [:]

    private let remoteVersion: String?
    private var resultsCache: [String: String] = [:]

    /// The supplied connection should already be authenticated.
    public init(
        connection: BaseConnection,
        remoteVersion: String? = nil
    ) async throws {
        self.connection = connection
        self.remoteVersion = remoteVersion

        try await Task.sleep(nanoseconds: 3_000_000_000)
        self.initialBuffer = try await connection.readChannel()
    }

    /// Return the most likely device type, or `nil` when no signature matches.
    @discardableResult
    public func autodetect() async -> String? {
        for (deviceType, rule) in SSHAutodetectMapper.orderedRules {
            let accuracy: Int
            switch rule.strategy {
            case .standard:
                accuracy = await autodetectStandard(
                    command: rule.command,
                    searchPatterns: rule.searchPatterns,
                    priority: rule.priority
                )
            case .loginBanner:
                accuracy = autodetectLoginBanner(
                    searchPatterns: rule.searchPatterns,
                    priority: rule.priority
                )
            case .remoteVersion:
                accuracy = autodetectRemoteVersion(
                    searchPatterns: rule.searchPatterns,
                    priority: rule.priority
                )
            }

            if accuracy > 0 {
                potentialMatches[deviceType] = accuracy
                if accuracy >= 99 {
                    let best = bestMatch()
                    await connection.disconnect()
                    if best == "cisco_wlc_85" {
                        return "cisco_wlc"
                    }
                    if best == "cisco_xr_2" {
                        return "cisco_xr"
                    }
                    return best
                }
            }
        }

        let result = bestMatch()
        await connection.disconnect()
        return result
    }

    private func bestMatch() -> String? {
        potentialMatches.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }?.key
    }

    private func sendCommand(_ command: String) async throws -> String {
        let lineEnding = connection.profile.returnCharacter
        try await connection.writeChannel(command + lineEnding)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        var output = ""
        let deadline = Date().addingTimeInterval(6.0)
        while Date() < deadline {
            output += try await connection.readChannel()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return stripBackspaces(output)
    }

    private func cachedCommand(_ command: String) async throws -> String {
        if let cached = resultsCache[command] {
            return cached
        }
        let response = try await sendCommand(command)
        resultsCache[command] = response
        return response
    }

    private func autodetectRemoteVersion(
        searchPatterns: [String],
        priority: Int
    ) -> Int {
        guard let remoteVersion, !remoteVersion.isEmpty else {
            return 0
        }
        return searchPatterns.contains {
            matches($0, in: remoteVersion)
        } ? priority : 0
    }

    private func autodetectLoginBanner(
        searchPatterns: [String],
        priority: Int
    ) -> Int {
        searchPatterns.contains {
            matches($0, in: initialBuffer)
        } ? priority : 0
    }

    private func autodetectStandard(
        command: String,
        searchPatterns: [String],
        priority: Int
    ) async -> Int {
        guard !command.isEmpty, !searchPatterns.isEmpty else {
            return 0
        }
        do {
            let response = try await cachedCommand(command)
            let invalidResponses = [
                "% Invalid input detected",
                "syntax error, expecting",
                "Error: Unrecognized command",
                "%Error",
                "command not found",
                "Syntax Error: unexpected argument",
                "% Unrecognized command found at",
                "% Unknown command, the error locates at"
            ]
            if invalidResponses.contains(where: { matches($0, in: response) }) {
                return 0
            }
            return searchPatterns.contains {
                matches($0, in: response)
            } ? priority : 0
        } catch {
            return 0
        }
    }

    private func matches(_ pattern: String, in value: String) -> Bool {
        value.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func stripBackspaces(_ value: String) -> String {
        var result = value
        while let range = result.range(of: #".\u{08}"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.replacingOccurrences(of: "\u{08}", with: "")
    }
}
