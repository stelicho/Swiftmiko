// Tests/SwiftmikoTests/SCPHandlerRegressionTests.swift
//
// Direct behavioral coverage for bugs found in a fresh adversarial
// pass over the SCP/file-transfer layer:
//
//  - remoteSpaceAvailable() applied the "kbytes" x1000 multiplier
//    based on an independent re-search of the WHOLE output, rather
//    than Netmiko's match.group(0) (the text THIS match actually
//    captured) — an unrelated "Kbytes free" elsewhere in a
//    multi-filesystem `dir` listing could multiply the wrong number.
//
//  - remoteSpaceAvailableUnix() required an EXACT "Avail" token in the
//    header row, rather than Netmiko's substring-of-the-4th-column
//    check — rejecting the "Available" header label some *nix `df`
//    variants use.
//
//  - checkFileExists() accepted a bare substring-containment fallback
//    that real Netmiko doesn't have, silently succeeding on output
//    shapes real Netmiko would throw on as unparseable.
//
//  - SCPHandler's *Unix helpers never dropped into a raw shell first
//    (Netmiko's _enter_shell()/_return_cli() around /bin/ls, /bin/df),
//    even for drivers (Arista, Linux-family) that already have a real
//    enterShell()/returnCLI() implementation sitting unused.

import XCTest
@testable import Swiftmiko

final class SCPHandlerRegressionTests: XCTestCase {
    private func testProfile(deviceType: String) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: deviceType,
            username: "netadmin",
            auth: .none
        )
    }

    private func makeTempFile() -> String {
        let path = NSTemporaryDirectory() + "swiftmiko-scp-regression-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: path, contents: Data("test".utf8))
        return path
    }

    // MARK: - remoteSpaceAvailable(): kbytes multiplier scope

    func testRemoteSpaceAvailableAppliesKbytesMultiplierOnlyToItsOwnMatchedText() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"), channel: channel)
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let handler = try await SCPHandler(
            connection: connection,
            sourceFile: tempFile,
            destinationFile: "dest.bin",
            fileSystem: "flash:",
            direction: .put,
            hashSupported: false
        )

        // The actual matched text ("100000 bytes free") has no "kbytes"
        // in it — an unrelated line elsewhere mentioning Kbytes must
        // not cause the x1000 multiplier to apply here.
        channel.enqueueOutput("100000 bytes free\nflash2: 50 Kbytes free (unrelated)\nrouter#")

        let available = try await handler.remoteSpaceAvailable()
        XCTAssertEqual(available, 100_000, "an unrelated 'Kbytes' mention elsewhere must not scale this match")
    }

    func testRemoteSpaceAvailableStillAppliesMultiplierWhenKbytesIsInTheActualMatch() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"), channel: channel)
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let handler = try await SCPHandler(
            connection: connection,
            sourceFile: tempFile,
            destinationFile: "dest.bin",
            fileSystem: "flash:",
            direction: .put,
            hashSupported: false
        )

        channel.enqueueOutput("500 Kbytes free\nrouter#")

        let available = try await handler.remoteSpaceAvailable()
        XCTAssertEqual(available, 500_000, "kbytes IN the matched text must still scale the result")
    }

    // MARK: - remoteSpaceAvailableUnix(): header column check

    func testRemoteSpaceAvailableUnixAcceptsAvailableHeaderVariant() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"), channel: channel)
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let handler = try await SCPHandler(
            connection: connection,
            sourceFile: tempFile,
            destinationFile: "dest.bin",
            fileSystem: "/var/tmp",
            direction: .put,
            hashSupported: false
        )

        // Before the fix, an exact-token "Avail" check would reject this
        // BSD-style "Available" header even though real Netmiko accepts
        // it (it only checks "Avail" as a SUBSTRING of the 4th column).
        channel.enqueueOutput(
            "Filesystem 1K-blocks Used Available Capacity Mounted on\n" +
            "/dev/sda1 1000000 200000 800000 20% /\n#"
        )

        let available = try await handler.remoteSpaceAvailableUnix()
        XCTAssertEqual(available, 800_000 * 1_024)
    }

    // MARK: - checkFileExists(): no lenient substring fallback

    func testCheckFileExistsThrowsOnUnparseableOutputRatherThanSucceedingViaSubstringFallback() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"), channel: channel)
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let handler = try await SCPHandler(
            connection: connection,
            sourceFile: tempFile,
            destinationFile: "dest.bin",
            fileSystem: "flash:",
            direction: .put,
            hashSupported: false
        )

        // Mentions the destination filename, but NOT in the
        // "Directory of ... <file>" shape real Netmiko requires.
        channel.enqueueOutput("unexpected garbage mentioning dest.bin somewhere\nrouter#")

        do {
            _ = try await handler.checkFileExists()
            XCTFail("Expected checkFileExists() to throw on unparseable output")
        } catch {
            // Expected — before the fix, the substring fallback would
            // have returned true instead.
        }
    }

    func testCheckFileExistsStillSucceedsOnTheRealDirectoryOfShape() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"), channel: channel)
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let handler = try await SCPHandler(
            connection: connection,
            sourceFile: tempFile,
            destinationFile: "dest.bin",
            fileSystem: "flash:",
            direction: .put,
            hashSupported: false
        )

        channel.enqueueOutput("Directory of flash:/\n 42  -rw-  1234  Jan 1 2026 dest.bin\nrouter#")

        let exists = try await handler.checkFileExists()
        XCTAssertTrue(exists)
    }

    // MARK: - SCPHandler's *Unix helpers now enter/exit a raw shell first

    func testCheckFileExistsUnixEntersAndExitsTheBourneShellOnArista() async throws {
        let channel = ScriptedChannel(responses: [
            "arista#",              // enterShell(): sendCommand("bash", expectString: "[\\$#]")
            "dest.bin arista-bash$", // the /bin/ls command itself, expectString "[#$]"
            "arista#",              // returnCLI(): sendCommand("exit", expectString: "[#>]")
        ])
        try await channel.open()
        let connection = AristaSSH(profile: testProfile(deviceType: "arista_eos"), channel: channel)
        let tempFile = makeTempFile()
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let handler = try await AristaFileTransfer(
            connection: connection,
            sourceFile: tempFile,
            destFile: "dest.bin",
            direction: .put
        )

        let exists = try await handler.checkFileExists()

        XCTAssertTrue(exists)
        // Before the fix, neither of these was ever sent — SCPHandler's
        // generic checkFileExistsUnix() had no way to reach Arista's
        // already-implemented enterShell()/returnCLI().
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("bash") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("exit") })
    }
}
