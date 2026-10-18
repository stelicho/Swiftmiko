// Tests/SwiftmikoTests/SpecialLoginHandlerTests.swift
//
// Regression coverage for specialLoginHandler() being defined in ~15
// driver files but never declared on BaseConnection and never called
// from anywhere — the override keyword didn't even exist, so none of
// these methods were reachable polymorphically. Fixed by declaring a
// no-op `open func specialLoginHandler(delay:)` on BaseConnection
// (matching netmiko's own no-op base implementation) and calling it
// from connect(), right after authenticate() and before
// sessionPreparation() — but only for SSH channels, matching
// netmiko's establish_connection(), which never calls it for the
// Telnet/Serial paths (those run their own telnet_login()/
// serial_login() instead).
//
// The compiler itself now guarantees every one of those ~15 driver
// methods is a real override of this base declaration — if the base
// declaration's signature didn't match, none of them would compile.

import XCTest
@testable import Swiftmiko

final class SpecialLoginHandlerTests: XCTestCase {
    private func testProfile(deviceType: String, password: String? = nil) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: deviceType,
            username: "netadmin",
            auth: password.map { .password($0) } ?? .none
        )
    }

    func testDefaultSpecialLoginHandlerIsANoOp() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoSSHConnection(
            profile: testProfile(deviceType: "cisco_ios"),
            channel: channel
        )

        try await connection.specialLoginHandler()

        XCTAssertTrue(channel.writes.isEmpty)
    }

    func testCiscoWlcSpecialLoginHandlerReturnsImmediatelyWhenAlreadyAtPrompt() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoWlcSSH(
            profile: testProfile(deviceType: "cisco_wlc"),
            channel: channel
        )
        channel.enqueueOutput("WLC-5508>")

        try await connection.specialLoginHandler()

        XCTAssertTrue(channel.writes.isEmpty)
    }

    func testCiscoWlcSpecialLoginHandlerThrowsOnUnexpectedBanner() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoWlcSSH(
            profile: testProfile(deviceType: "cisco_wlc"),
            channel: channel
        )
        // Contains a ">" (so the generic promptPattern short-circuits the
        // read immediately, avoiding a slow real-timeout wait), but not
        // at end-of-line and with none of the known login substrings —
        // so specialLoginHandler's own stricter check still rejects it.
        channel.enqueueOutput("garbage > more unexpected text")

        await XCTAssertThrowsErrorAsync(try await connection.specialLoginHandler())
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // Expected.
    }
}
