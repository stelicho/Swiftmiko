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
// Sources/SwiftmikoCLI/SwiftmikoEncrypt.swift
//
// Port of netmiko_encrypt.py.

import ArgumentParser
import Foundation

public struct SwiftmikoEncrypt: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiftmiko-encrypt",
        abstract: "Encrypt data using Swiftmiko's encryption."
    )

    @Argument(help: "The data to encrypt")
    var data: String?

    @Option(help: "The encryption key (if not provided, will use SWIFTMIKO_TOOLS_KEY env variable)")
    var key: String?

    @Option(name: .customLong("type"), help: "Encryption type (if not provided, will read from .swiftmiko.yml)")
    var encryptionType: String?

    public init() {}

    public func run() throws {
        let value = data ?? promptSecure("Enter the data to encrypt: ")

        let keyData: Data
        if let key {
            keyData = Data(key.utf8)
        } else {
            keyData = try getEncryptionKey()
        }

        let type: String
        if let encryptionType {
            type = encryptionType
        } else {
            let config = try loadSwiftmikoYAML()
            type = config.metaEncryptionType
        }

        let encrypted = try encryptValue(value, key: keyData, type: type)
        print("\nEncrypted data: \(encrypted)\n")
    }
}
