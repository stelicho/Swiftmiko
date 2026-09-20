// Tests/SwiftmikoTests/SNMPAutodetectTests.swift
//
// Test suite for SNMPDetect/SNMPAutodetectMapper (Sources/SNMPAutodetect.swift).
// SNMPDetect takes its wire transport through the injectable SNMPTransport
// protocol rather than talking SNMP itself, which makes the whole
// autodetection algorithm — OID selection, priority/tiebreak ordering,
// response caching — testable without a real device or `pysnmp`-equivalent
// dependency, the same way BufferedChannel makes the SSH drivers testable.

import XCTest
@testable import Swiftmiko

/// Records every OID queried (and how many times) and returns a canned
/// response per OID, standing in for a real SNMP GET.
private final class MockSNMPTransport: SNMPTransport, @unchecked Sendable {
    var responses: [String: String] = [:]
    private(set) var callCounts: [String: Int] = [:]

    func get(
        hostname: String,
        port: Int,
        oid: String,
        credentials: SNMPCredentials
    ) async throws -> String? {
        callCounts[oid, default: 0] += 1
        return responses[oid]
    }
}

final class SNMPAutodetectTests: XCTestCase {

    // MARK: - SNMPDetect.init validation

    func testInitRequiresACommunityForV1() {
        XCTAssertThrowsError(
            try SNMPDetect(hostname: "203.0.113.1", snmpVersion: .v1, community: nil)
        ) { error in
            XCTAssertEqual(error as? SNMPDetectError, .communityRequired)
        }
    }

    func testInitRejectsAnEmptyCommunityForV2c() {
        XCTAssertThrowsError(
            try SNMPDetect(hostname: "203.0.113.1", snmpVersion: .v2c, community: "")
        ) { error in
            XCTAssertEqual(error as? SNMPDetectError, .communityRequired)
        }
    }

    func testInitAcceptsANonEmptyCommunityForV1() throws {
        XCTAssertNoThrow(
            try SNMPDetect(hostname: "203.0.113.1", snmpVersion: .v1, community: "public")
        )
    }

    func testInitRequiresAUserForV3() {
        XCTAssertThrowsError(
            try SNMPDetect(hostname: "203.0.113.1", snmpVersion: .v3, user: "")
        ) { error in
            XCTAssertEqual(error as? SNMPDetectError, .userRequired)
        }
    }

    func testDefaultVersionIsV3AndStillRequiresAUser() {
        // No version/user supplied at all — defaults to v3, so this should
        // fail the same way an explicit v3-with-no-user call would.
        XCTAssertThrowsError(try SNMPDetect(hostname: "203.0.113.1")) { error in
            XCTAssertEqual(error as? SNMPDetectError, .userRequired)
        }
    }

    func testInitAcceptsANonEmptyUserForV3() {
        XCTAssertNoThrow(
            try SNMPDetect(hostname: "203.0.113.1", snmpVersion: .v3, user: "pysnmp")
        )
    }

    // MARK: - autodetect()

    func testAutodetectMatchesTheHighestPriorityRuleOnTheSharedSysDescrOID() async throws {
        let transport = MockSNMPTransport()
        transport.responses[".1.3.6.1.2.1.1.1.0"] = "Arista Networks EOS version 4.28.0F"

        let detector = try SNMPDetect(
            hostname: "203.0.113.1", snmpVersion: .v2c, community: "public", transport: transport
        )
        let result = try await detector.autodetect()

        XCTAssertEqual(result, "arista_eos")
    }

    func testAutodetectMatchesADeviceWithItsOwnDistinctOID() async throws {
        let transport = MockSNMPTransport()
        // Shared sysDescr OID resolves to something that matches nothing.
        transport.responses[".1.3.6.1.2.1.1.1.0"] = "Generic Linux Server"
        // Check Point's rule uses its own OID instead of sysDescr.
        transport.responses[".1.3.6.1.4.1.2620.1.6.16.9.0"] = "CheckPoint"

        let detector = try SNMPDetect(
            hostname: "203.0.113.1", snmpVersion: .v2c, community: "public", transport: transport
        )
        let result = try await detector.autodetect()

        XCTAssertEqual(result, "checkpoint")
    }

    func testAutodetectReturnsNilWhenNothingMatches() async throws {
        let transport = MockSNMPTransport()
        transport.responses[".1.3.6.1.2.1.1.1.0"] = "Unrecognized Device Banner"

        let detector = try SNMPDetect(
            hostname: "203.0.113.1", snmpVersion: .v2c, community: "public", transport: transport
        )
        let result = try await detector.autodetect()

        XCTAssertNil(result)
    }

    func testAutodetectQueriesEachDistinctOIDOnlyOnceEvenThoughManyRulesShareIt() async throws {
        // Roughly a dozen rules in SNMPAutodetectMapper share the plain
        // sysDescr OID — if caching regresses, this call count jumps from
        // 1 to "however many rules use that OID."
        let transport = MockSNMPTransport()
        transport.responses[".1.3.6.1.2.1.1.1.0"] = "Nothing matches this banner text"

        let detector = try SNMPDetect(
            hostname: "203.0.113.1", snmpVersion: .v2c, community: "public", transport: transport
        )
        _ = try await detector.autodetect()

        XCTAssertEqual(transport.callCounts[".1.3.6.1.2.1.1.1.0"], 1)
    }

    func testAutodetectThrowsWhenNoTransportWasSupplied() async throws {
        let detector = try SNMPDetect(
            hostname: "203.0.113.1", snmpVersion: .v2c, community: "public"
        )
        do {
            _ = try await detector.autodetect()
            XCTFail("Expected autodetect() to throw without a transport")
        } catch let error as SNMPDetectError {
            XCTAssertEqual(error, .transportUnavailable)
        }
    }

    func testAutodetectMatchingIsCaseInsensitive() async throws {
        let transport = MockSNMPTransport()
        transport.responses[".1.3.6.1.2.1.1.1.0"] = "mikrotik routeros 7.15"

        let detector = try SNMPDetect(
            hostname: "203.0.113.1", snmpVersion: .v2c, community: "public", transport: transport
        )
        let result = try await detector.autodetect()

        XCTAssertEqual(result, "mikrotik_routeros")
    }

    // MARK: - SNMPAutodetectMapper

    func testEveryRuleHasAValidRegexPattern() {
        for (deviceType, rule) in SNMPAutodetectMapper.rules {
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: rule.pattern),
                "\(deviceType)'s pattern '\(rule.pattern)' is not a valid regex"
            )
        }
    }

    func testCompatibilityAliasesMatchTheRealMapper() {
        XCTAssertEqual(SNMP_MAPPER_BASE.keys.sorted(), SNMPAutodetectMapper.rules.keys.sorted())
        XCTAssertEqual(SNMP_MAPPER.keys.sorted(), SNMPAutodetectMapper.rules.keys.sorted())
    }

    // MARK: - identifyAddressType

    func testIdentifyAddressTypeRecognizesIPv4() {
        XCTAssertEqual(identifyAddressType("192.168.1.1"), ["IPv4"])
        XCTAssertEqual(identifyAddressType("255.255.255.255"), ["IPv4"])
    }

    func testIdentifyAddressTypeRejectsOutOfRangeOctets() {
        XCTAssertEqual(identifyAddressType("999.999.999.999"), [])
        XCTAssertEqual(identifyAddressType("256.1.1.1"), [])
    }

    func testIdentifyAddressTypeRejectsIncompleteIPv4() {
        XCTAssertEqual(identifyAddressType("10.0.0"), [])
    }

    func testIdentifyAddressTypeRecognizesIPv6() {
        XCTAssertEqual(identifyAddressType("::1"), ["IPv6"])
        XCTAssertEqual(identifyAddressType("2001:db8::1"), ["IPv6"])
    }

    func testIdentifyAddressTypeRejectsHostnames() {
        XCTAssertEqual(identifyAddressType("cisco1.lasthop.io"), [])
        XCTAssertEqual(identifyAddressType(""), [])
    }

    func testSnakeCaseAliasMatchesCamelCaseFunction() {
        for entry in ["192.168.1.1", "::1", "not-an-ip"] {
            XCTAssertEqual(identify_address_type(entry), identifyAddressType(entry))
        }
    }
}
