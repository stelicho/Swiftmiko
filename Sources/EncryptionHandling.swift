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
//
//  EncryptionHandling.swift
//  Swiftmiko
//
//  Transport-neutral secret encryption hooks.
//

import Foundation

public enum EncryptionHandlingError: Error {
    case providerUnavailable
    case invalidCiphertext
}

/// Implement this protocol when inventory files need encrypted credentials.
///
/// The Python implementation delegates this concern to the configured
/// Netmiko encryption mechanism. Swiftmiko keeps credentials out of the
/// utility layer and makes the provider explicit.
public protocol SecretEncryptor: AnyObject {
    func encrypt(_ plaintext: String) throws -> String
    func decrypt(_ ciphertext: String) throws -> String
}

/// Explicit no-op provider for callers that store credentials elsewhere.
public final class PlaintextSecretEncryptor: SecretEncryptor {
    public init() {}

    public func encrypt(_ plaintext: String) throws -> String {
        plaintext
    }

    public func decrypt(_ ciphertext: String) throws -> String {
        ciphertext
    }
}
