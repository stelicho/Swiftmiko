// Tests/SwiftmikoTests/BaseConnectionTests.swift
import XCTest
@testable import Swiftmiko

final class BaseConnectionTests: XCTestCase {
    func testSendCommandStripsEchoAndPromptFromInjectedChannel() async throws {
        let channel = BufferedChannel()
        try await channel.open()

        let profile = ConnectionProfile(
            host: "203.0.113.1",
            deviceType: "cisco_ios",
            username: "netadmin",
            auth: .none
        )
        let connection = CiscoSSHConnection(profile: profile, channel: channel)
        connection.basePrompt = "Router#"

        channel.enqueueOutput("show version\nSoftware Version 1.0\nRouter#")
        let output = try await connection.sendCommand("show version")

        XCTAssertEqual(channel.writes, ["show version\n"])
        XCTAssertEqual(output, "Software Version 1.0")
    }
}
