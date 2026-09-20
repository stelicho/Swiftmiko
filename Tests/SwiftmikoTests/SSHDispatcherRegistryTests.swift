// Tests/SwiftmikoTests/SSHDispatcherRegistryTests.swift
//
// Regression coverage for SSHDispatcher.defaultConnectionFactories: every
// registered deviceType should produce a live connection instance of the
// right deviceType without crashing, even before any network I/O happens.
// This is the cheapest possible guard against a future edit silently
// breaking one of the ~230 factory closures (typo'd class name, a custom
// init that force-unwraps something the test profile doesn't supply, etc).

import XCTest
@testable import Swiftmiko

final class SSHDispatcherRegistryTests: XCTestCase {
    func testEveryRegisteredConnectionFactoryConstructsWithoutCrashing() {
        for deviceType in SSHDispatcher.platforms {
            let profile = ConnectionProfile(
                host: "203.0.113.1",
                deviceType: deviceType,
                username: "netadmin",
                auth: .none
            )
            let factory = SSHDispatcher.defaultConnectionFactories[deviceType]
            XCTAssertNotNil(factory, "No factory registered for \(deviceType)")
            let connection = factory?(profile)
            XCTAssertNotNil(connection, "Factory for \(deviceType) returned nil")
            XCTAssertEqual(
                connection?.profile.deviceType, deviceType,
                "Factory for \(deviceType) built a connection with a different deviceType"
            )
        }
    }

    func testEveryRegisteredFileTransferFactoryHasAMatchingConnectionType() {
        // Every SCP-capable deviceType should also be a connectable
        // deviceType — a file transfer with nothing to transfer over isn't
        // meaningful.
        for deviceType in SSHDispatcher.scpPlatforms {
            XCTAssertTrue(
                SSHDispatcher.platforms.contains(deviceType),
                "\(deviceType) has a file-transfer factory but no connection factory"
            )
        }
    }

    // MARK: - connectHandler's channel-selection routing
    //
    // These mirror SerialChannelTests' equivalent check for the "_serial"
    // branch of connectHandler's suffix logic — verifying the other two
    // branches (plain SSH, and "_telnet") each assign the right concrete
    // Channel type, not just that *some* channel got assigned. All use
    // autoConnect: false so nothing here ever touches a real socket.

    func testConnectHandlerRoutesPlainDeviceTypesToAnSSHChannel() async throws {
        let profile = ConnectionProfile(
            host: "203.0.113.1",
            deviceType: "cisco_ios",
            username: "netadmin",
            auth: .none
        )
        let connection = try await SSHDispatcher.connectHandler(profile: profile, autoConnect: false)
        XCTAssertTrue(connection.channel is NIOSSHChannel)
    }

    func testConnectHandlerRoutesTelnetDeviceTypesToATelnetChannel() async throws {
        let profile = ConnectionProfile(
            host: "203.0.113.1",
            deviceType: "cisco_ios_telnet",
            username: "netadmin",
            auth: .none
        )
        let connection = try await SSHDispatcher.connectHandler(profile: profile, autoConnect: false)
        XCTAssertTrue(connection.channel is NIOTelnetChannel)
    }

    func testEveryTelnetDeviceTypeRoutesToATelnetChannelNotAnSSHChannel() async throws {
        // Broader sweep: every "_telnet"-suffixed deviceType in the
        // registry, not just one representative sample. This is the
        // regression test for the nioSSHChannelProvider →
        // nioTelnetChannelProvider fix across all 58 telnet entries.
        for deviceType in SSHDispatcher.platforms where deviceType.hasSuffix("_telnet") {
            let profile = ConnectionProfile(
                host: "203.0.113.1",
                deviceType: deviceType,
                username: "netadmin",
                auth: .none
            )
            let connection = try await SSHDispatcher.connectHandler(profile: profile, autoConnect: false)
            XCTAssertTrue(
                connection.channel is NIOTelnetChannel,
                "\(deviceType) did not route to NIOTelnetChannel"
            )
        }
    }
}
