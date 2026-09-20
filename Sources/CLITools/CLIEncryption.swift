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
// Sources/SwiftmikoCLI/CLIEncryption.swift
//
// Port of the parts of netmiko/encryption_handling.py the CLI tools
// call: get_encryption_key(), encrypt_value(), and (implied)
// decrypt_value()/decrypt_config().
//
// GAP: Fernet is not implemented — see the earlier design note.
// Only aes128 is real, via AES-GCM (not wire-compatible with
// Netmiko's own aes128 unless that's also GCM-based).

import Foundation
import Crypto

enum EncryptionType: String { case fernet, aes128 }

enum SwiftmikoEncryptionError: Error, CustomStringConvertible {
    case fernetNotImplemented
    case invalidKeyLength
    case decryptionFailed

    var description: String {
        switch self {
        case .fernetNotImplemented:
            return "Fernet encryption is not yet implemented in Swiftmiko. Use --type aes128."
        case .invalidKeyLength:
            return "Encryption key must decode to exactly 16 bytes for AES-128."
        case .decryptionFailed:
            return "Failed to decrypt value — wrong key or corrupted ciphertext."
        }
    }
}

func getEncryptionKey() throws -> Data {
    guard let keyString = ProcessInfo.processInfo.environment["SWIFTMIKO_TOOLS_KEY"] else {
        throw CLIToolError.encryptionKeyNotProvided
    }
    return Data(keyString.utf8)
}

func encryptValue(_ value: String, key: Data, type: String) throws -> String {
    guard let encryptionType = EncryptionType(rawValue: type) else {
        throw SwiftmikoEncryptionError.decryptionFailed
    }
    switch encryptionType {
    case .fernet:
        throw SwiftmikoEncryptionError.fernetNotImplemented
    case .aes128:
        guard key.count == 16 else { throw SwiftmikoEncryptionError.invalidKeyLength }
        let sealedBox = try AES.GCM.seal(Data(value.utf8), using: SymmetricKey(data: key))
        guard let combined = sealedBox.combined else { throw SwiftmikoEncryptionError.decryptionFailed }
        return combined.base64EncodedString()
    }
}

func decryptValue(_ encoded: String, key: Data, type: String) throws -> String {
    guard let encryptionType = EncryptionType(rawValue: type) else {
        throw SwiftmikoEncryptionError.decryptionFailed
    }
    switch encryptionType {
    case .fernet:
        throw SwiftmikoEncryptionError.fernetNotImplemented
    case .aes128:
        guard key.count == 16, let data = Data(base64Encoded: encoded) else {
            throw SwiftmikoEncryptionError.decryptionFailed
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw SwiftmikoEncryptionError.decryptionFailed
        }
        return string
    }
}

func decryptConfig(
    _ devices: [String: YAMLDeviceEntry], key: Data, type: String
) throws -> [String: YAMLDeviceEntry] {
    var result = devices
    for (name, entry) in devices {
        guard case .device(var params) = entry else { continue }
        if let password = params["password"] { params["password"] = try decryptValue(password, key: key, type: type) }
        if let secret = params["secret"] { params["secret"] = try decryptValue(secret, key: key, type: type) }
        result[name] = .device(params)
    }
    return result
}
