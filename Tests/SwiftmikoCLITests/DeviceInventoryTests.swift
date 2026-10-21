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
// Tests/SwiftmikoCLITests/DeviceInventoryTests.swift
//
// Coverage for DeviceInventory.swift's device/group resolution and
// ConnectionProfile construction — previously untested despite having
// several distinct validation/error branches. obtainDevices() itself
// reads from $SWIFTMIKO_TOOLS_CFG (not a pure function, unlike
// obtainAllDevices/updateDeviceParams/connectionProfile(from:)), so
// those tests point that env var at a temp YAML file for the duration
// of the test, following the same cross-platform setenv/_putenv_s
// pattern TextFSMIndexTableTests.swift already established.

import XCTest
@testable import SwiftmikoCLI

final class DeviceInventoryTests: XCTestCase {

    // MARK: - obtainAllDevices (pure)

    func testObtainAllDevicesReturnsOnlyDeviceEntriesNotGroups() {
        let config = SwiftmikoYAMLConfig(
            metaEncryption: false,
            metaEncryptionType: "fernet",
            devices: [
                "rtr1": .device(["host": "10.0.0.1"]),
                "rtr2": .device(["host": "10.0.0.2"]),
                "core-routers": .group(["rtr1", "rtr2"]),
            ]
        )
        let result = obtainAllDevices(config)
        XCTAssertEqual(Set(result.keys), ["rtr1", "rtr2"])
        XCTAssertEqual(result["rtr1"], ["host": "10.0.0.1"])
    }

    func testObtainAllDevicesReturnsEmptyWhenThereAreNoDeviceEntries() {
        let config = SwiftmikoYAMLConfig(
            metaEncryption: false, metaEncryptionType: "fernet",
            devices: ["onlygroup": .group(["a", "b"])]
        )
        XCTAssertTrue(obtainAllDevices(config).isEmpty)
    }

    // MARK: - updateDeviceParams (pure)

    func testUpdateDeviceParamsOverridesOnlyProvidedFieldsAndPreservesTheRest() {
        let base: DeviceParams = ["host": "10.0.0.1", "username": "olduser", "device_type": "cisco_ios"]
        let updated = updateDeviceParams(base, username: "newuser", password: "hunter2", secret: nil)

        XCTAssertEqual(updated["username"], "newuser")
        XCTAssertEqual(updated["password"], "hunter2")
        XCTAssertNil(updated["secret"])
        XCTAssertEqual(updated["host"], "10.0.0.1")
        XCTAssertEqual(updated["device_type"], "cisco_ios")
    }

    func testUpdateDeviceParamsIsANoOpWhenAllOverridesAreNil() {
        let base: DeviceParams = ["host": "10.0.0.1", "username": "admin"]
        XCTAssertEqual(updateDeviceParams(base, username: nil, password: nil, secret: nil), base)
    }

    // MARK: - connectionProfile(from:) (pure)

    func testConnectionProfileBuildsFromCompleteParams() throws {
        let params: DeviceParams = [
            "host": "10.0.0.1",
            "device_type": "cisco_ios",
            "username": "admin",
            "password": "hunter2",
            "secret": "enablepw",
            "port": "2222",
        ]
        let profile = try connectionProfile(from: params)

        XCTAssertEqual(profile.host, "10.0.0.1")
        XCTAssertEqual(profile.deviceType, "cisco_ios")
        XCTAssertEqual(profile.username, "admin")
        XCTAssertEqual(profile.secret, "enablepw")
        XCTAssertEqual(profile.port, 2222)
        guard case .password(let password) = profile.auth else {
            return XCTFail("expected .password auth, got \(profile.auth)")
        }
        XCTAssertEqual(password, "hunter2")
    }

    func testConnectionProfileFallsBackToIPKeyWhenHostIsMissing() throws {
        let params: DeviceParams = ["ip": "10.0.0.5", "device_type": "cisco_ios", "username": "admin"]
        let profile = try connectionProfile(from: params)
        XCTAssertEqual(profile.host, "10.0.0.5")
    }

    func testConnectionProfileThrowsWhenHostAndIPAreBothMissing() {
        let params: DeviceParams = ["device_type": "cisco_ios", "username": "admin"]
        XCTAssertThrowsError(try connectionProfile(from: params))
    }

    func testConnectionProfileThrowsWhenDeviceTypeIsMissing() {
        let params: DeviceParams = ["host": "10.0.0.1", "username": "admin"]
        XCTAssertThrowsError(try connectionProfile(from: params))
    }

    func testConnectionProfileThrowsWhenUsernameIsMissing() {
        let params: DeviceParams = ["host": "10.0.0.1", "device_type": "cisco_ios"]
        XCTAssertThrowsError(try connectionProfile(from: params))
    }

    func testConnectionProfileDefaultsToNoAuthWhenPasswordIsAbsent() throws {
        let params: DeviceParams = ["host": "10.0.0.1", "device_type": "cisco_ios", "username": "admin"]
        let profile = try connectionProfile(from: params)
        guard case .none = profile.auth else {
            return XCTFail("expected .none auth, got \(profile.auth)")
        }
    }

    func testConnectionProfileIgnoresAnUnparseablePortAndKeepsTheDefault() throws {
        let defaultPort = try connectionProfile(
            from: ["host": "10.0.0.1", "device_type": "cisco_ios", "username": "admin"]
        ).port
        let params: DeviceParams = [
            "host": "10.0.0.1", "device_type": "cisco_ios", "username": "admin", "port": "not-a-number",
        ]
        XCTAssertEqual(try connectionProfile(from: params).port, defaultPort)
    }

    // MARK: - obtainDevices (reads $SWIFTMIKO_TOOLS_CFG — real file I/O)

    private static let sampleYAML = """
    __meta__:
      encryption: false
    rtr1:
      host: 10.0.0.1
      device_type: cisco_ios
      username: admin
    rtr2:
      host: 10.0.0.2
      device_type: cisco_ios
      username: admin
    core-routers:
      - rtr1
      - rtr2
    broken-group:
      - rtr1
      - does-not-exist
    """

    /// Writes the sample YAML to a temp file and points
    /// $SWIFTMIKO_TOOLS_CFG at it for the duration of `body`, restoring
    /// whatever the env var was set to beforehand afterward.
    private func withSampleInventory(_ body: () throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent(".swiftmiko.yml")
        try Self.sampleYAML.write(to: configFile, atomically: true, encoding: .utf8)

        let previousEnv = ProcessInfo.processInfo.environment["SWIFTMIKO_TOOLS_CFG"]
        Self.setEnvironmentVariable("SWIFTMIKO_TOOLS_CFG", configFile.path)
        defer {
            if let previousEnv {
                Self.setEnvironmentVariable("SWIFTMIKO_TOOLS_CFG", previousEnv)
            } else {
                Self.unsetEnvironmentVariable("SWIFTMIKO_TOOLS_CFG")
            }
        }

        try body()
    }

    func testObtainDevicesReturnsASingleNamedDevice() throws {
        try withSampleInventory {
            let result = try obtainDevices("rtr1")
            XCTAssertEqual(result.keys.count, 1)
            XCTAssertEqual(result["rtr1"]?["host"], "10.0.0.1")
        }
    }

    func testObtainDevicesExpandsAGroupToItsMemberDevices() throws {
        try withSampleInventory {
            let result = try obtainDevices("core-routers")
            XCTAssertEqual(Set(result.keys), ["rtr1", "rtr2"])
        }
    }

    func testObtainDevicesAllReturnsEveryDeviceButNotGroups() throws {
        try withSampleInventory {
            let result = try obtainDevices("all")
            XCTAssertEqual(Set(result.keys), ["rtr1", "rtr2"])
        }
    }

    func testObtainDevicesThrowsForAnUnknownDeviceOrGroupName() throws {
        try withSampleInventory {
            XCTAssertThrowsError(try obtainDevices("does-not-exist"))
        }
    }

    func testObtainDevicesThrowsWhenAGroupMemberDoesNotResolveToARealDevice() throws {
        try withSampleInventory {
            XCTAssertThrowsError(try obtainDevices("broken-group"))
        }
    }

    /// setenv/unsetenv aren't available on Windows (ucrt uses _putenv_s
    /// instead) — same pattern TextFSMIndexTableTests.swift already uses.
    private static func setEnvironmentVariable(_ name: String, _ value: String) {
        #if os(Windows)
        _ = _putenv_s(name, value)
        #else
        setenv(name, value, 1)
        #endif
    }

    private static func unsetEnvironmentVariable(_ name: String) {
        #if os(Windows)
        _ = _putenv_s(name, "")
        #else
        unsetenv(name)
        #endif
    }
}
