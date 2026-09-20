// Tests/SwiftmikoTests/RedispatchTests.swift
//
// Regression coverage for SSHDispatcher.redispatch(_:deviceType:sessionPreparation:).
// The whole point of the fix this covers: unlike Netmiko's in-place
// obj.__class__ reassignment, Swift has to build a new driver instance —
// but it must reuse the *same* channel the original connection already
// had open, not silently open a second one. If a future edit regresses
// that (e.g. going back to reconnecting via connectHandler), this test
// catches it without needing a real device.

import XCTest
@testable import Swiftmiko

final class RedispatchTests: XCTestCase {
    func testRedispatchReusesTheExistingChannelInsteadOfOpeningANewOne() async throws {
        let channel = BufferedChannel()
        try await channel.open()

        let profile = ConnectionProfile(
            host: "203.0.113.1",
            deviceType: "cisco_ios",
            username: "netadmin",
            auth: .none
        )
        let original = CiscoIOSSSH(profile: profile, channel: channel)

        let redispatched = try await SSHDispatcher.redispatch(
            original,
            deviceType: "cisco_nxos",
            sessionPreparation: false
        )

        XCTAssertTrue(redispatched is CiscoSSHConnection)
        XCTAssertEqual(redispatched.profile.deviceType, "cisco_nxos")
        XCTAssertEqual(redispatched.profile.host, profile.host)

        // Same physical channel — not a fresh connection.
        channel.enqueueOutput("show version\nNX-OS\nswitch#")
        redispatched.basePrompt = "switch#"
        _ = try await redispatched.sendCommand("show version")
        XCTAssertEqual(channel.writes, ["show version\n"])
    }

    func testRedispatchThrowsForAnUnregisteredDeviceType() async throws {
        let channel = BufferedChannel()
        try await channel.open()

        let profile = ConnectionProfile(
            host: "203.0.113.1",
            deviceType: "cisco_ios",
            username: "netadmin",
            auth: .none
        )
        let original = CiscoIOSSSH(profile: profile, channel: channel)

        do {
            _ = try await SSHDispatcher.redispatch(
                original,
                deviceType: "not_a_real_device_type"
            )
            XCTFail("Expected redispatch to throw for an unregistered deviceType")
        } catch {
            // Expected.
        }
    }
}
