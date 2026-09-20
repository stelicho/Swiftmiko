// Tests/SwiftmikoTests/SCPDispatcherRegistryTests.swift
//
// Regression coverage for SSHDispatcher.defaultFileTransferFactories:
// every registered SCP deviceType should produce a live SCPHandler
// instance, using the *same* connection instance its own connection
// factory would build — this is what actually exercises the `as?`
// casts in the dell_sonic/nokia_sros/zpe_nodegrid closures (each of
// those requires the connection to be its own concrete driver type,
// not a generic BaseConnection).
//
// Uses direction: .put with a real local temp file and an explicit
// fileSystem, which is the one combination SCPHandler.init can
// complete without any network I/O (no remote MD5, no remote file
// size lookup, no Cisco filesystem autodetection).

import XCTest
@testable import Swiftmiko

final class SCPDispatcherRegistryTests: XCTestCase {
    func testEveryRegisteredFileTransferFactoryConstructsAgainstItsOwnConnectionType() async throws {
        let tempFile = NSTemporaryDirectory() + "swiftmiko-scp-test-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: tempFile, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        for deviceType in SSHDispatcher.scpPlatforms {
            let profile = ConnectionProfile(
                host: "203.0.113.1",
                deviceType: deviceType,
                username: "netadmin",
                auth: .none
            )
            guard let connectionFactory = SSHDispatcher.defaultConnectionFactories[deviceType] else {
                XCTFail("\(deviceType) has no connection factory to pair with its file-transfer factory")
                continue
            }
            guard let transferFactory = SSHDispatcher.defaultFileTransferFactories[deviceType] else {
                XCTFail("No file-transfer factory registered for \(deviceType)")
                continue
            }

            let connection = connectionFactory(profile)

            do {
                let handler = try await transferFactory(
                    connection,
                    tempFile,
                    "remote-destination.txt",
                    "/explicit/test/filesystem",
                    .put,
                    nil
                )
                XCTAssertEqual(handler.sourceFile, tempFile, "\(deviceType) transfer handler has the wrong sourceFile")
                XCTAssertEqual(
                    handler.destinationFile, "remote-destination.txt",
                    "\(deviceType) transfer handler has the wrong destinationFile"
                )
            } catch {
                XCTFail("File-transfer factory for \(deviceType) threw: \(error)")
            }
        }
    }

    func testMakeFileTransferRoutesThroughTheDeviceTypeOnTheConnection() async throws {
        // Exercises the public SSHDispatcher.makeFileTransfer API end to
        // end, not just the raw dictionary entry, for a representative
        // sample: a generic one, and the three that require a cast.
        let tempFile = NSTemporaryDirectory() + "swiftmiko-scp-test-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: tempFile, contents: Data("test".utf8))
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        for deviceType in ["linux", "dell_sonic", "nokia_sros", "zpe_nodegrid"] {
            let profile = ConnectionProfile(
                host: "203.0.113.1", deviceType: deviceType,
                username: "netadmin", auth: .none
            )
            let connection = SSHDispatcher.defaultConnectionFactories[deviceType]!(profile)
            let handler = try await SSHDispatcher.makeFileTransfer(
                connection: connection,
                sourceFile: tempFile,
                destinationFile: "remote-destination.txt",
                fileSystem: "/explicit/test/filesystem",
                direction: .put
            )
            XCTAssertEqual(handler.sourceFile, tempFile)
        }
    }
}
