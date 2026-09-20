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
// Sources/SwiftmikoCLI/SwiftmikoBulkEncrypt.swift
//
// Port of netmiko_bulk_encrypt.py.
//
// GAP: Yams doesn't preserve comments/key order/quoting the way
// ruamel.yaml does — this WILL reformat the whole file, not just
// the password/secret fields. See earlier design note.

import ArgumentParser
import Foundation
import Yams

public struct SwiftmikoBulkEncrypt: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiftmiko-bulk-encrypt",
        abstract: "Encrypt passwords in .swiftmiko.yml file"
    )

    @Option(help: "Input .swiftmiko.yml file")
    var inputFile: String = "~/.swiftmiko.yml"

    @Option(help: "Output .swiftmiko.yml file with encrypted passwords (default: stdout)")
    var outputFile: String?

    @Option(name: .customLong("encryption-type"), help: "Encryption type to use")
    var encryptionType: String = "fernet"

    public init() {}

    public func run() throws {
        let expandedInput = (inputFile as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expandedInput),
              let contents = String(data: data, encoding: .utf8) else {
            throw DeviceInventoryError.fileNotFound(expandedInput)
        }
        guard var config = try Yams.load(yaml: contents) as? [String: Any] else {
            throw DeviceInventoryError.malformedYAML("root is not a mapping")
        }

        let key = try getEncryptionKey()
        for (deviceName, value) in config {
            guard var params = value as? [String: Any] else { continue }
            if let password = params["password"] as? String {
                params["password"] = try encryptValue(password, key: key, type: encryptionType)
            }
            if let secret = params["secret"] as? String {
                params["secret"] = try encryptValue(secret, key: key, type: encryptionType)
            }
            config[deviceName] = params
        }

        let output = try Yams.dump(object: config)
        if let outputFile {
            let expandedOutput = (outputFile as NSString).expandingTildeInPath
            try output.write(toFile: expandedOutput, atomically: true, encoding: .utf8)
            FileHandle.standardError.write("Encrypted .swiftmiko.yml file has been written to \(expandedOutput)\n".data(using: .utf8)!)
        } else {
            print(output)
        }
    }
}
