// Tests/SwiftmikoTests/SerialChannelTests.swift
//
// Test suite for the serial transport (Sources/SerialChannel.swift) and
// its dispatcher wiring. Unlike SSH/Telnet/SNMP, SerialChannel talks
// directly to a POSIX tty via termios — there's no injectable protocol
// to fake a real port with, so this suite covers what's actually
// testable without hardware:
//   1. SerialSettings, a plain value type.
//   2. SerialChannel's own error handling (bad port path, using the
//      channel before opening it) — deterministic and hardware-free.
//   3. SSHDispatcher's "_serial" suffix routing, using autoConnect:
//      false so it never actually touches a real port.
//   4. The CLI driver logic (CiscoIOSSerial) against a BufferedChannel —
//      the same substitution BaseConnectionTests.swift uses for SSH,
//      since a driver's sendCommand/prompt handling is transport-agnostic
//      and works identically over any Channel conformance.
//
// Actually opening a real serial port is exactly the kind of thing
// TESTING.md's "verify against real/emulated hardware" section is for,
// not something to fake here.

import XCTest
@testable import Swiftmiko

final class SerialChannelTests: XCTestCase {

    // MARK: - SerialSettings

    func testSerialSettingsDefaultsMatchNetmikosDefaults() {
        let settings = SerialSettings.default
        XCTAssertEqual(settings.baudRate, 9600)
        XCTAssertEqual(settings.dataBits, 8)
        XCTAssertEqual(settings.stopBits, 1)
        XCTAssertEqual(settings.parity, .none)
    }

    func testSerialSettingsCustomValuesRoundTrip() {
        let settings = SerialSettings(baudRate: 115_200, dataBits: 7, stopBits: 2, parity: .even)
        XCTAssertEqual(settings.baudRate, 115_200)
        XCTAssertEqual(settings.dataBits, 7)
        XCTAssertEqual(settings.stopBits, 2)
        XCTAssertEqual(settings.parity, .even)
    }

    func testSerialSettingsEquatable() {
        XCTAssertEqual(SerialSettings(), SerialSettings())
        XCTAssertNotEqual(SerialSettings(baudRate: 9600), SerialSettings(baudRate: 115_200))
    }

    // MARK: - SerialChannel error handling (no real port needed)

    func testOpenThrowsForANonexistentPortPath() async throws {
        let profile = ConnectionProfile(
            host: "/dev/cu.this-port-does-not-exist-swiftmiko-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        let channel = SerialChannel(profile: profile)

        do {
            try await channel.open()
            XCTFail("Expected open() to throw for a nonexistent serial port")
        } catch is SwiftmikoError {
            // Expected — the exact message is platform-dependent (strerror text).
        }
    }

    func testWriteThrowsChannelClosedBeforeOpening() async throws {
        let profile = ConnectionProfile(
            host: "/dev/cu.this-port-does-not-exist-swiftmiko-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        let channel = SerialChannel(profile: profile)
        XCTAssertFalse(channel.isOpen)

        do {
            try await channel.write("test\n")
            XCTFail("Expected write() to throw before open()")
        } catch SwiftmikoError.channelClosed {
            // Expected.
        }
    }

    func testReadAvailableThrowsChannelClosedBeforeOpening() async throws {
        let profile = ConnectionProfile(
            host: "/dev/cu.this-port-does-not-exist-swiftmiko-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        let channel = SerialChannel(profile: profile)

        do {
            _ = try await channel.readAvailable()
            XCTFail("Expected readAvailable() to throw before open()")
        } catch SwiftmikoError.channelClosed {
            // Expected.
        }
    }

    func testCloseIsSafeToCallWithoutEverOpening() async {
        let profile = ConnectionProfile(
            host: "/dev/cu.this-port-does-not-exist-swiftmiko-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        let channel = SerialChannel(profile: profile)
        await channel.close()
        XCTAssertFalse(channel.isOpen)
    }

    func testSerialChannelProviderBuildsASerialChannel() async throws {
        let profile = ConnectionProfile(
            host: "/dev/cu.usbserial-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        let channel = try await serialChannelProvider(profile)
        XCTAssertTrue(channel is SerialChannel)
    }

    // MARK: - SSHDispatcher "_serial" suffix routing

    func testConnectHandlerRoutesSerialDeviceTypesToASerialChannel() async throws {
        let profile = ConnectionProfile(
            host: "/dev/cu.usbserial-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        // autoConnect: false — this must never try to touch a real port.
        let connection = try await SSHDispatcher.connectHandler(profile: profile, autoConnect: false)

        XCTAssertTrue(connection is CiscoIOSSerial)
        XCTAssertTrue(connection.channel is SerialChannel)
    }

    func testFurukawaFitelnetSerialIsRegisteredAndRoutesToASerialChannel() async throws {
        let profile = ConnectionProfile(
            host: "/dev/cu.usbserial-test",
            deviceType: "furukawa_fitelnet_serial",
            username: "netadmin",
            auth: .none
        )
        let connection = try await SSHDispatcher.connectHandler(profile: profile, autoConnect: false)

        XCTAssertTrue(connection is FurukawaFitelnetSerial)
        XCTAssertTrue(connection.channel is SerialChannel)
    }

    // MARK: - decodeAvailableText(): split multi-byte UTF-8 across reads
    //
    // Regression coverage for a bug found in a fresh adversarial pass:
    // a multi-byte UTF-8 character split across two separate read()
    // calls used to fall back to Latin-1 decoding for the chunk
    // containing the partial sequence, misreading it as separate
    // single-byte characters instead of correctly buffering the
    // dangling bytes until the rest of the sequence arrives.

    func testDecodeAvailableTextBuffersADanglingPartialMultiByteCharacter() {
        // "café" — the trailing "é" is 2 UTF-8 bytes (0xC3 0xA9); only
        // the first byte arrived so far.
        var buffer = Data("caf".utf8)
        buffer.append(0xC3)

        let (text, remaining) = SerialChannel.decodeAvailableText(from: buffer)

        XCTAssertEqual(text, "caf", "the lone partial byte must not corrupt the already-complete prefix")
        XCTAssertEqual(remaining, Data([0xC3]), "the dangling byte must be buffered, not decoded as Latin-1 garbage")
    }

    func testDecodeAvailableTextCompletesTheCharacterOnceTheRestArrives() {
        // The continuation byte for "é" (0xA9) arrives in the next chunk.
        let buffer = Data([0xC3, 0xA9])

        let (text, remaining) = SerialChannel.decodeAvailableText(from: buffer)

        XCTAssertEqual(text, "é")
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDecodeAvailableTextFallsBackToLatin1ForGenuinelyNonUTF8Data() {
        // 0xFF is never a valid UTF-8 byte in any position — this isn't
        // a split character, it's just not UTF-8 at all.
        let buffer = Data([0xFF, 0xFE])

        let (text, remaining) = SerialChannel.decodeAvailableText(from: buffer)

        XCTAssertEqual(text, String(bytes: buffer, encoding: .isoLatin1))
        XCTAssertTrue(remaining.isEmpty, "the whole buffer should be consumed by the Latin-1 fallback")
    }

    func testDecodeAvailableTextReturnsEmptyForAnEmptyBuffer() {
        let (text, remaining) = SerialChannel.decodeAvailableText(from: Data())
        XCTAssertEqual(text, "")
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Driver logic over a fake channel (transport-agnostic)

    func testCiscoIOSSerialSendCommandStripsEchoAndPromptJustLikeSSH() async throws {
        // Same substitution BaseConnectionTests.swift uses for SSH — the
        // driver's command handling doesn't know or care what Channel
        // conformance it's actually talking to.
        let channel = BufferedChannel()
        try await channel.open()

        let profile = ConnectionProfile(
            host: "/dev/cu.usbserial-test",
            deviceType: "cisco_ios_serial",
            username: "netadmin",
            auth: .none
        )
        let connection = CiscoIOSSerial(profile: profile, channel: channel)
        connection.basePrompt = "Router#"

        channel.enqueueOutput("show version\nSoftware Version 1.0\nRouter#")
        let output = try await connection.sendCommand("show version")

        XCTAssertEqual(channel.writes, ["show version\n"])
        XCTAssertEqual(output, "Software Version 1.0")
    }
}
