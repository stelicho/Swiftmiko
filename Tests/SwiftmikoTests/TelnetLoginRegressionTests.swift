// Tests/SwiftmikoTests/TelnetLoginRegressionTests.swift
//
// Direct behavioral coverage for two bugs found in a fresh adversarial
// pass over BaseConnection.telnetLogin() — the generic login algorithm
// nearly every Telnet driver depends on (either directly, or
// indirectly via an override that only installs IAC negotiation and
// then calls super.telnetLogin() for the actual exchange). Found by
// comparing structurally against real Netmiko's telnet_login(), not
// just its default parameter values:
//
//  1. The prior version used readUntilPattern() — a BLOCKING
//     wait-for-pattern primitive — as its only per-iteration read, and
//     wrote nothing if no pattern matched yet. Real Netmiko writes a
//     bare TELNET_RETURN at the end of every non-matching iteration to
//     nudge a silent device into producing its next line. Without
//     that nudge, a device that prints a banner and then waits for a
//     keypress before showing "login:" would just time out.
//
//  2. The prior defaults ("#" / ">") were unanchored substring
//     searches, so a stray "#"/">" anywhere in banner text (not at the
//     end of a line) could cause a false-positive early return before
//     username/password were ever sent. Real Netmiko's own defaults
//     anchor to end-of-line specifically to avoid this.

import XCTest
@testable import Swiftmiko

final class TelnetLoginRegressionTests: XCTestCase {
    private func testProfile(password: String? = nil) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: "generic_telnet",
            username: "netadmin",
            auth: password.map { .password($0) } ?? .none,
            globalDelayFactor: 0.01
        )
    }

    func testTelnetLoginNudgesASilentDeviceWithABareReturnBeforeTheLoginPromptAppears() async throws {
        let channel = ScriptedChannel(responses: [
            "Welcome to the device. Press any key.\n",  // silent banner — no prompt yet
            "login: ",                                   // appears only after the nudge
            "assword: ",
            "host#",
        ])
        try await channel.open()
        let connection = BaseConnection(
            profile: testProfile(password: "hunter2"),
            channel: channel
        )

        _ = try await connection.telnetLogin()

        // Before the fix, nothing was ever written between reads — the
        // loop just called readUntilPattern() again, which would have
        // timed out against this scripted sequence instead of ever
        // reaching the login prompt.
        XCTAssertTrue(channel.writes.contains("\r\n"), "expected a bare nudge write after the silent banner")
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("netadmin") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("hunter2") })
    }

    func testTelnetLoginDoesNotMistakeAStrayHashInBannerTextForThePrompt() async throws {
        let channel = ScriptedChannel(responses: [
            "Welcome! Use # to list commands.\n",  // "#" NOT at end of line
            "login: ",
            "assword: ",
            "host#",
        ])
        try await channel.open()
        let connection = BaseConnection(
            profile: testProfile(password: "hunter2"),
            channel: channel
        )

        _ = try await connection.telnetLogin()

        // Before the fix, the unanchored "#" default would match the
        // banner's "Use # to list commands." on the very first read and
        // return immediately — username/password would never be sent.
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("netadmin") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("hunter2") })
    }
}
