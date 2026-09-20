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
//  SNMPAutodetect.swift
//  Swiftmiko
//
//  Port of netmiko/snmp_autodetect.py
//

import Foundation

public enum SNMPVersion: String, Sendable {
    case v1
    case v2c
    case v3
}

public enum SNMPAuthProtocol: String, Sendable {
    case sha
    case md5
}

public enum SNMPPrivacyProtocol: String, Sendable {
    case des
    case tripleDES = "3des"
    case aes128
    case aes192
    case aes256
}

public struct SNMPCredentials: Sendable {
    public let version: SNMPVersion
    public let community: String?
    public let user: String
    public let authenticationKey: String
    public let privacyKey: String
    public let authenticationProtocol: SNMPAuthProtocol
    public let privacyProtocol: SNMPPrivacyProtocol

    public init(
        version: SNMPVersion,
        community: String?,
        user: String,
        authenticationKey: String,
        privacyKey: String,
        authenticationProtocol: SNMPAuthProtocol,
        privacyProtocol: SNMPPrivacyProtocol
    ) {
        self.version = version
        self.community = community
        self.user = user
        self.authenticationKey = authenticationKey
        self.privacyKey = privacyKey
        self.authenticationProtocol = authenticationProtocol
        self.privacyProtocol = privacyProtocol
    }
}

/// Adapter for a Swift SNMP implementation.
public protocol SNMPTransport: AnyObject {
    func get(
        hostname: String,
        port: Int,
        oid: String,
        credentials: SNMPCredentials
    ) async throws -> String?
}

public struct SNMPAutodetectRule: Sendable {
    public let oid: String
    public let pattern: String
    public let priority: Int

    public init(oid: String, pattern: String, priority: Int) {
        self.oid = oid
        self.pattern = pattern
        self.priority = priority
    }
}

public enum SNMPAutodetectMapper {
    public static let rules: [String: SNMPAutodetectRule] = [
        "arista_eos": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Arista Networks EOS.*", priority: 99),
        "allied_telesis_awplus": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*AlliedWare Plus.*", priority: 99),
        "paloalto_panos": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Palo Alto Networks.*", priority: 99),
        "hp_comware": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*HP(E)? Comware.*", priority: 99),
        "hp_procurve": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".ProCurve", priority: 99),
        "cisco_ios": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Cisco IOS Software.*,.*", priority: 60),
        "cisco_xe": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*IOS-XE Software,.*", priority: 99),
        "cisco_xr": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Cisco IOS XR Software.*", priority: 99),
        "cisco_asa": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Cisco Adaptive Security Appliance.*", priority: 99),
        "cisco_nxos": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Cisco NX-OS.*", priority: 99),
        "cisco_wlc": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Cisco Controller.*", priority: 99),
        "f5_tmsh": .init(oid: ".1.3.6.1.4.1.3375.2.1.4.1.0", pattern: ".*BIG-IP.*", priority: 99),
        "fortinet": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: "Forti.*", priority: 80),
        "checkpoint": .init(oid: ".1.3.6.1.4.1.2620.1.6.16.9.0", pattern: "CheckPoint", priority: 79),
        "juniper_junos": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Juniper.*", priority: 99),
        "nokia_sros": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*TiMOS.*", priority: 99),
        "dell_powerconnect": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: "PowerConnect.*", priority: 50),
        "mikrotik_routeros": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*RouterOS.*", priority: 60),
        "hirschmann_hios": .init(oid: ".1.3.6.1.2.1.1.1.0", pattern: ".*Hirschmann BOBCAT.*", priority: 60)
    ]
}

// Compatibility names matching the Python module-level mappings.
public let SNMP_MAPPER_BASE = SNMPAutodetectMapper.rules
public let SNMP_MAPPER = SNMPAutodetectMapper.rules

public enum SNMPDetectError: Error, Equatable {
    case invalidVersion
    case communityRequired
    case userRequired
    case invalidAuthenticationProtocol
    case invalidPrivacyProtocol
    case transportUnavailable
}

/// Return the literal IP address families present in an entry.
///
/// DNS resolution is deliberately left to the injected SNMP transport. This
/// keeps this pure helper deterministic and avoids resolving hostnames twice.
public func identifyAddressType(_ entry: String) -> [String] {
    let ipv4Pattern = #"^(?:\d{1,3}\.){3}\d{1,3}$"#
    if entry.range(of: ipv4Pattern, options: .regularExpression) != nil {
        let octets = entry.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 && octets.allSatisfy({ (0...255).contains($0) }) {
            return ["IPv4"]
        }
    }

    // This intentionally validates the common IPv6 forms without requiring
    // a platform-specific socket module.
    if entry.contains(":"),
       entry.range(
        of: #"^[0-9A-Fa-f:]+$"#,
        options: .regularExpression
       ) != nil {
        return ["IPv6"]
    }
    return []
}

public func identify_address_type(_ entry: String) -> [String] {
    identifyAddressType(entry)
}

/// SNMPv1/v2c/v3 device autodetection.
public class SNMPDetect {
    public let hostname: String
    public let snmpVersion: SNMPVersion
    public let snmpPort: Int
    public let credentials: SNMPCredentials

    private let transport: SNMPTransport?
    private var responseCache: [String: String] = [:]

    public init(
        hostname: String,
        snmpVersion: SNMPVersion = .v3,
        snmpPort: Int = 161,
        community: String? = nil,
        user: String = "",
        authenticationKey: String = "",
        privacyKey: String = "",
        authenticationProtocol: SNMPAuthProtocol = .sha,
        privacyProtocol: SNMPPrivacyProtocol = .aes128,
        transport: SNMPTransport? = nil
    ) throws {
        switch snmpVersion {
        case .v1, .v2c:
            guard let community, !community.isEmpty else {
                throw SNMPDetectError.communityRequired
            }
        case .v3:
            guard !user.isEmpty else {
                throw SNMPDetectError.userRequired
            }
        }

        self.hostname = hostname
        self.snmpVersion = snmpVersion
        self.snmpPort = snmpPort
        self.transport = transport
        self.credentials = SNMPCredentials(
            version: snmpVersion,
            community: community,
            user: user,
            authenticationKey: authenticationKey,
            privacyKey: privacyKey,
            authenticationProtocol: authenticationProtocol,
            privacyProtocol: privacyProtocol
        )
    }

    /// Query each unique OID once and return the highest-priority match.
    @discardableResult
    public func autodetect() async throws -> String? {
        let ordered = SNMPAutodetectMapper.rules.sorted {
            if $0.value.priority == $1.value.priority {
                return $0.key < $1.key
            }
            return $0.value.priority > $1.value.priority
        }

        for (deviceType, rule) in ordered {
            let response = try await response(for: rule.oid)
            guard !response.isEmpty else { continue }
            if response.range(
                of: rule.pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                return deviceType
            }
        }
        return nil
    }

    private func response(for oid: String) async throws -> String {
        if let cached = responseCache[oid] {
            return cached
        }
        guard let transport else {
            throw SNMPDetectError.transportUnavailable
        }
        let value = try await transport.get(
            hostname: hostname,
            port: snmpPort,
            oid: oid,
            credentials: credentials
        ) ?? ""
        responseCache[oid] = value
        return value
    }
}
