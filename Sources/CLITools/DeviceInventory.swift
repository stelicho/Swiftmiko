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
// Sources/SwiftmikoCLI/DeviceInventory.swift
//
// Port of helpers.py's obtain_devices()/update_device_params() plus
// the .swiftmiko.yml loading netmiko.utilities.load_netmiko_yml()
// provides.

import Foundation
import Yams
import Swiftmiko

typealias DeviceParams = [String: String]

enum YAMLDeviceEntry {
    case device(DeviceParams)
    case group([String])
}

struct SwiftmikoYAMLConfig {
    var metaEncryption: Bool
    var metaEncryptionType: String
    var devices: [String: YAMLDeviceEntry]
}

enum DeviceInventoryError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case deviceOrGroupNotFound(String)
    case malformedYAML(String)

    var description: String {
        switch self {
        case .fileNotFound(let path): return "Could not find .swiftmiko.yml at \(path)"
        case .deviceOrGroupNotFound(let name):
            return "Error reading from swiftmiko devices file. Device or group not found: \(name)"
        case .malformedYAML(let detail): return "Malformed .swiftmiko.yml: \(detail)"
        }
    }
}

func loadSwiftmikoYAML() throws -> SwiftmikoYAMLConfig {
    let path = ProcessInfo.processInfo.environment["SWIFTMIKO_TOOLS_CFG"]
        ?? (NSHomeDirectory() as NSString).appendingPathComponent(".swiftmiko.yml")

    guard let data = FileManager.default.contents(atPath: path),
          let contents = String(data: data, encoding: .utf8) else {
        throw DeviceInventoryError.fileNotFound(path)
    }
    guard let root = try Yams.load(yaml: contents) as? [String: Any] else {
        throw DeviceInventoryError.malformedYAML("root is not a mapping")
    }

    let meta = root["__meta__"] as? [String: Any] ?? [:]
    let encryption = meta["encryption"] as? Bool ?? false
    let encryptionType = meta["encryption_type"] as? String ?? "fernet"

    var devices: [String: YAMLDeviceEntry] = [:]
    for (key, value) in root where key != "__meta__" {
        if let list = value as? [String] {
            devices[key] = .group(list)
        } else if let dict = value as? [String: Any] {
            let stringified = dict.reduce(into: DeviceParams()) { $0[$1.key] = String(describing: $1.value) }
            devices[key] = .device(stringified)
        }
    }
    return SwiftmikoYAMLConfig(metaEncryption: encryption, metaEncryptionType: encryptionType, devices: devices)
}

func obtainAllDevices(_ config: SwiftmikoYAMLConfig) -> [String: DeviceParams] {
    var result: [String: DeviceParams] = [:]
    for (name, entry) in config.devices {
        if case .device(let params) = entry { result[name] = params }
    }
    return result
}

func obtainDevices(_ deviceOrGroup: String) throws -> [String: DeviceParams] {
    var config = try loadSwiftmikoYAML()

    if config.metaEncryption {
        let key = try getEncryptionKey()
        config.devices = try decryptConfig(config.devices, key: key, type: config.metaEncryptionType)
    }

    if deviceOrGroup == "all" { return obtainAllDevices(config) }

    guard let entry = config.devices[deviceOrGroup] else {
        throw DeviceInventoryError.deviceOrGroupNotFound(deviceOrGroup)
    }
    switch entry {
    case .group(let names):
        var result: [String: DeviceParams] = [:]
        for name in names {
            guard case .device(let params)? = config.devices[name] else {
                throw DeviceInventoryError.deviceOrGroupNotFound(name)
            }
            result[name] = params
        }
        return result
    case .device(let params):
        return [deviceOrGroup: params]
    }
}

func updateDeviceParams(
    _ params: DeviceParams, username: String?, password: String?, secret: String?
) -> DeviceParams {
    var updated = params
    if let username { updated["username"] = username }
    if let password { updated["password"] = password }
    if let secret { updated["secret"] = secret }
    return updated
}

func connectionProfile(from params: DeviceParams) throws -> ConnectionProfile {
    guard let host = params["host"] ?? params["ip"] else {
        throw DeviceInventoryError.malformedYAML("missing host/ip")
    }
    guard let deviceType = params["device_type"] else {
        throw DeviceInventoryError.malformedYAML("missing device_type")
    }
    guard let username = params["username"] else {
        throw DeviceInventoryError.malformedYAML("missing username")
    }
    let auth: AuthMethod = params["password"].map { .password($0) } ?? .none
    var profile = ConnectionProfile(
        host: host, deviceType: deviceType, username: username,
        auth: auth, secret: params["secret"]
    )
    if let portString = params["port"], let port = Int(portString) { profile.port = port }
    return profile
}

func displayInventory(_ config: SwiftmikoYAMLConfig) {
    for (name, entry) in config.devices.sorted(by: { $0.key < $1.key }) {
        switch entry {
        case .device: print(name)
        case .group(let members): print("\(name): \(members.joined(separator: ", "))")
        }
    }
}
