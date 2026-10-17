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
// Wire-compatible port of netmiko/encryption_handling.py: both
// get_encryption_key() and the PBKDF2-HMAC-SHA256 (100k rounds,
// random 16-byte salt) -> Fernet / AES-128-CBC+PKCS7 split match
// the Python implementation byte-for-byte, so a `.swiftmiko.yml`
// (or `.netmiko.yml`) encrypted by one tool decrypts cleanly in
// the other. See encryption_handling.py on the netmiko develop
// branch for the reference implementation this was checked against.

import Foundation
import Crypto
import _CryptoExtras

enum EncryptionType: String { case fernet, aes128 }

enum SwiftmikoEncryptionError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case decryptionFailed

    var description: String {
        switch self {
        case .unsupportedType(let type):
            return "Unsupported encryption type: \(type)"
        case .decryptionFailed:
            return "Failed to decrypt value — wrong key or corrupted ciphertext."
        }
    }
}

private let encryptionPrefix = "__encrypt__"

func getEncryptionKey() throws -> Data {
    guard let keyString = ProcessInfo.processInfo.environment["SWIFTMIKO_TOOLS_KEY"] else {
        throw CLIToolError.encryptionKeyNotProvided
    }
    return Data(keyString.utf8)
}

/// PBKDF2HMAC(SHA256, length=32, iterations=100_000) — Netmiko's exact
/// parameters. The "safe" PBKDF2 overload in _CryptoExtras rejects
/// anything under 210k rounds, so matching the real wire format
/// requires the explicit unsafeUncheckedRounds escape hatch.
private func deriveKey(from key: Data, salt: Data) throws -> Data {
    let symmetricKey = try KDF.Insecure.PBKDF2.deriveKey(
        from: key,
        salt: salt,
        using: .sha256,
        outputByteCount: 32,
        unsafeUncheckedRounds: 100_000
    )
    return symmetricKey.withUnsafeBytes { Data($0) }
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
}

private func base64URLDecode(_ string: String) -> Data? {
    let base64 = string
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    return Data(base64Encoded: base64)
}

/// Builds a standard Fernet token: 0x80 version byte + 8-byte
/// big-endian Unix timestamp + 16-byte IV + AES-128-CBC/PKCS7
/// ciphertext + 32-byte HMAC-SHA256 over everything before it.
private func fernetEncrypt(plaintext: Data, signingKey: Data, encryptionKey: Data) throws -> Data {
    let iv = AES._CBC.IV()
    let ciphertext = try AES._CBC.encrypt(plaintext, using: SymmetricKey(data: encryptionKey), iv: iv)

    var payload = Data([0x80])
    payload.append(withUnsafeBytes(of: UInt64(Date().timeIntervalSince1970).bigEndian) { Data($0) })
    payload.append(Data(iv))
    payload.append(ciphertext)

    let hmac = HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: signingKey))
    payload.append(Data(hmac))
    return payload
}

private func fernetDecrypt(token: Data, signingKey: Data, encryptionKey: Data) throws -> Data {
    guard token.count >= 1 + 8 + 16 + 32, token.first == 0x80 else {
        throw SwiftmikoEncryptionError.decryptionFailed
    }
    let hmacStart = token.index(token.endIndex, offsetBy: -32)
    let payload = token[token.startIndex..<hmacStart]
    let receivedHMAC = token[hmacStart...]

    guard HMAC<SHA256>.isValidAuthenticationCode(receivedHMAC, authenticating: payload, using: SymmetricKey(data: signingKey)) else {
        throw SwiftmikoEncryptionError.decryptionFailed
    }

    let ivStart = token.index(token.startIndex, offsetBy: 9)
    let ivEnd = token.index(ivStart, offsetBy: 16)
    let iv = try AES._CBC.IV(ivBytes: Array(token[ivStart..<ivEnd]))
    let ciphertext = token[ivEnd..<hmacStart]
    return try AES._CBC.decrypt(ciphertext, using: SymmetricKey(data: encryptionKey), iv: iv)
}

func encryptValue(_ value: String, key: Data, type: String) throws -> String {
    guard let encryptionType = EncryptionType(rawValue: type) else {
        throw SwiftmikoEncryptionError.unsupportedType(type)
    }
    let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    let derivedKey = try deriveKey(from: key, salt: salt)

    let encrypted: Data
    switch encryptionType {
    case .fernet:
        let token = try fernetEncrypt(
            plaintext: Data(value.utf8),
            signingKey: derivedKey.prefix(16),
            encryptionKey: derivedKey.suffix(16)
        )
        encrypted = Data(base64URLEncode(token).utf8)
    case .aes128:
        let iv = AES._CBC.IV()
        let ciphertext = try AES._CBC.encrypt(Data(value.utf8), using: SymmetricKey(data: derivedKey.prefix(16)), iv: iv)
        encrypted = Data(iv) + ciphertext
    }

    return "\(encryptionPrefix)\(salt.base64EncodedString()):\(encrypted.base64EncodedString())"
}

func decryptValue(_ encoded: String, key: Data, type: String) throws -> String {
    guard let encryptionType = EncryptionType(rawValue: type) else {
        throw SwiftmikoEncryptionError.unsupportedType(type)
    }

    let stripped = encoded.hasPrefix(encryptionPrefix)
        ? String(encoded.dropFirst(encryptionPrefix.count))
        : encoded
    let parts = stripped.split(separator: ":", maxSplits: 1)
    guard parts.count == 2,
          let salt = Data(base64Encoded: String(parts[0])),
          let payload = Data(base64Encoded: String(parts[1])) else {
        throw SwiftmikoEncryptionError.decryptionFailed
    }
    let derivedKey = try deriveKey(from: key, salt: salt)

    let plaintext: Data
    switch encryptionType {
    case .fernet:
        guard let tokenString = String(data: payload, encoding: .utf8),
              let token = base64URLDecode(tokenString) else {
            throw SwiftmikoEncryptionError.decryptionFailed
        }
        plaintext = try fernetDecrypt(
            token: token,
            signingKey: derivedKey.prefix(16),
            encryptionKey: derivedKey.suffix(16)
        )
    case .aes128:
        guard payload.count > 16 else { throw SwiftmikoEncryptionError.decryptionFailed }
        let ivEnd = payload.index(payload.startIndex, offsetBy: 16)
        let iv = try AES._CBC.IV(ivBytes: Array(payload[payload.startIndex..<ivEnd]))
        plaintext = try AES._CBC.decrypt(payload[ivEnd...], using: SymmetricKey(data: derivedKey.prefix(16)), iv: iv)
    }

    guard let string = String(data: plaintext, encoding: .utf8) else {
        throw SwiftmikoEncryptionError.decryptionFailed
    }
    return string
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
