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
// Tests/SwiftmikoCLITests/CLIEncryptionTests.swift
//
// The fernetReal/aes128Real vectors below were generated independently
// with Python's `cryptography` package, running Netmiko's actual
// encrypt_value() logic verbatim (PBKDF2HMAC-SHA256/100k + Fernet /
// AES-128-CBC+PKCS7), with a fixed salt (bytes 0..15) and, for aes128,
// a fixed IV (bytes 16..31). They exist to prove Swiftmiko's decryptValue
// is wire-compatible with real Netmiko ciphertext, not just internally
// consistent with itself.

import XCTest
@testable import SwiftmikoCLI

final class CLIEncryptionTests: XCTestCase {
    private let key = Data("swiftmiko-test-key".utf8)

    private let fernetReal =
        "__encrypt__AAECAwQFBgcICQoLDA0ODw==:Z0FBQUFBQnEwNnNJQVRxQloyWjd1c1MtamlpZ05ZUFlvMS1uUlhRcGdraEw1T3hVRXJQOXhHeW9XTFhrZElOX1pya0txV3htcDVkTjQ5WkhVeTFka0F1RFIwUmRiUS1nWUE9PQ=="
    private let aes128Real =
        "__encrypt__AAECAwQFBgcICQoLDA0ODw==:EBESExQVFhcYGRobHB0eHxO6Ya1K/pETIj9L8TCWhvA="

    func testDecryptsRealNetmikoFernetVector() throws {
        XCTAssertEqual(try decryptValue(fernetReal, key: key, type: "fernet"), "hunter2")
    }

    func testDecryptsRealNetmikoAES128Vector() throws {
        XCTAssertEqual(try decryptValue(aes128Real, key: key, type: "aes128"), "hunter2")
    }

    func testFernetRoundTrip() throws {
        let encrypted = try encryptValue("correct horse battery staple", key: key, type: "fernet")
        XCTAssertTrue(encrypted.hasPrefix("__encrypt__"))
        XCTAssertEqual(try decryptValue(encrypted, key: key, type: "fernet"), "correct horse battery staple")
    }

    func testAES128RoundTrip() throws {
        let encrypted = try encryptValue("correct horse battery staple", key: key, type: "aes128")
        XCTAssertTrue(encrypted.hasPrefix("__encrypt__"))
        XCTAssertEqual(try decryptValue(encrypted, key: key, type: "aes128"), "correct horse battery staple")
    }

    func testDecryptValueToleratesMissingPrefix() throws {
        let encrypted = try encryptValue("hunter2", key: key, type: "aes128")
        let stripped = String(encrypted.dropFirst("__encrypt__".count))
        XCTAssertEqual(try decryptValue(stripped, key: key, type: "aes128"), "hunter2")
    }

    func testWrongKeyFailsFernetDecryption() throws {
        let encrypted = try encryptValue("hunter2", key: key, type: "fernet")
        XCTAssertThrowsError(try decryptValue(encrypted, key: Data("wrong-key".utf8), type: "fernet"))
    }

    func testWrongKeyFailsAES128Decryption() throws {
        let encrypted = try encryptValue("hunter2", key: key, type: "aes128")
        XCTAssertThrowsError(try decryptValue(encrypted, key: Data("wrong-key".utf8), type: "aes128"))
    }

    func testTamperedFernetHMACFailsDecryption() throws {
        var encrypted = try encryptValue("hunter2", key: key, type: "fernet")
        encrypted.removeLast()
        encrypted.append(encrypted.last == "A" ? "B" : "A")
        XCTAssertThrowsError(try decryptValue(encrypted, key: key, type: "fernet"))
    }

    func testUnsupportedEncryptionTypeThrows() {
        XCTAssertThrowsError(try encryptValue("hunter2", key: key, type: "rot13"))
    }
}
