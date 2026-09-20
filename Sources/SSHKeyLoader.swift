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
//  SSHKeyLoader.swift
//  Swiftmiko
//
//  Loads an SSH private key from disk and wraps it in NIOSSHPrivateKey.
//
//  Supported formats:
//   • OpenSSH private key  (-----BEGIN OPENSSH PRIVATE KEY-----)
//     - ssh-ed25519, ecdsa-sha2-nistp256/384/521
//     - Unencrypted only (encrypted keys produce a clear error)
//   • SEC1 PEM             (-----BEGIN EC PRIVATE KEY-----)
//     - ecdsa-sha2-nistp256/384/521
//   • PKCS8 PEM            (-----BEGIN PRIVATE KEY-----)
//     - ecdsa-sha2-nistp256/384/521 and Ed25519
//
//  RSA is not supported by swift-nio-ssh and is rejected with a clear message.
//  Encrypted keys (passphrase-protected) are not supported; the caller
//  receives a message explaining how to strip the passphrase.
//

import Foundation
import CryptoKit
import NIOSSH
import NIOCore

// MARK: - SSHKeyLoader

enum SSHKeyLoader {

    static func load(path: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        let pem: String
        do {
            pem = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw SwiftmikoError.authenticationFailed(
                "Cannot read SSH key file '\(path)': \(error.localizedDescription)"
            )
        }
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") {
            return try parseOpenSSH(pem: trimmed, passphrase: passphrase)
        }
        if trimmed.hasPrefix("-----BEGIN EC PRIVATE KEY-----") {
            return try parseSEC1(pem: trimmed)
        }
        if trimmed.hasPrefix("-----BEGIN PRIVATE KEY-----") {
            return try parsePKCS8(pem: trimmed)
        }
        if trimmed.hasPrefix("-----BEGIN RSA PRIVATE KEY-----") ||
           trimmed.contains("RSA") {
            throw SwiftmikoError.notImplemented(
                "RSA private keys are not supported. " +
                "Convert to Ed25519: ssh-keygen -t ed25519 -f <new_key>"
            )
        }
        throw SwiftmikoError.authenticationFailed(
            "Unrecognised private key format in '\(path)'. " +
            "Expected OpenSSH, SEC1, or PKCS8 PEM."
        )
    }

    // MARK: - OpenSSH format

    private static func parseOpenSSH(pem: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        let der = try decodePEM(pem)
        var buf = SSHBuffer(der)

        // Magic header: "openssh-key-v1\0" (16 bytes)
        let magic = "openssh-key-v1\0"
        let header = try buf.readBytes(magic.utf8.count)
        guard header == Array(magic.utf8) else {
            throw SwiftmikoError.authenticationFailed("Not a valid OpenSSH private key (bad magic)")
        }

        let ciphername = String(bytes: try buf.readSSHString(), encoding: .utf8) ?? ""
        let kdfname    = String(bytes: try buf.readSSHString(), encoding: .utf8) ?? ""
        _              = try buf.readSSHString()  // kdfoptions

        if ciphername != "none" || kdfname != "none" {
            throw SwiftmikoError.authenticationFailed(
                "Passphrase-protected SSH keys are not supported. " +
                "Remove the passphrase first: ssh-keygen -p -N '' -f <keyfile>"
            )
        }

        let numKeys = try buf.readUInt32()
        guard numKeys >= 1 else {
            throw SwiftmikoError.authenticationFailed("OpenSSH key file contains no keys")
        }

        _ = try buf.readSSHString()  // public key blob — not needed

        let privateBlob = try buf.readSSHString()
        var priv = SSHBuffer(privateBlob)

        let check1 = try priv.readUInt32()
        let check2 = try priv.readUInt32()
        guard check1 == check2 else {
            throw SwiftmikoError.authenticationFailed(
                "OpenSSH private key checksum mismatch — the key may be corrupted"
            )
        }

        let keyType = String(bytes: try priv.readSSHString(), encoding: .utf8) ?? ""

        switch keyType {
        case "ssh-ed25519":
            return try parseOpenSSHEd25519(&priv)
        case "ecdsa-sha2-nistp256":
            return try parseOpenSSHECDSA(&priv, curve: .p256)
        case "ecdsa-sha2-nistp384":
            return try parseOpenSSHECDSA(&priv, curve: .p384)
        case "ecdsa-sha2-nistp521":
            return try parseOpenSSHECDSA(&priv, curve: .p521)
        default:
            throw SwiftmikoError.notImplemented(
                "SSH key type '\(keyType)' is not supported. " +
                "Supported: ssh-ed25519, ecdsa-sha2-nistp256/384/521"
            )
        }
    }

    private static func parseOpenSSHEd25519(_ priv: inout SSHBuffer) throws -> NIOSSHPrivateKey {
        _ = try priv.readSSHString()       // public key (32 bytes) — skip
        let privFull = try priv.readSSHString() // 64 bytes: seed (32) + public (32)
        guard privFull.count >= 32 else {
            throw SwiftmikoError.authenticationFailed("Ed25519 private key blob too short")
        }
        let seed = Data(privFull.prefix(32))
        do {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return NIOSSHPrivateKey(ed25519Key: key)
        } catch {
            throw SwiftmikoError.authenticationFailed(
                "Invalid Ed25519 key material: \(error.localizedDescription)"
            )
        }
    }

    private static func parseOpenSSHECDSA(_ priv: inout SSHBuffer, curve: ECCurve) throws -> NIOSSHPrivateKey {
        _ = try priv.readSSHString()  // curve name (e.g. "nistp256")
        _ = try priv.readSSHString()  // uncompressed public key point
        let scalar = try priv.readMPInt()
        return try makeECKey(scalar: scalar, curve: curve)
    }

    // MARK: - SEC1 PEM (-----BEGIN EC PRIVATE KEY-----)

    private static func parseSEC1(pem: String) throws -> NIOSSHPrivateKey {
        let der = try decodePEM(pem)
        let curve = sec1Curve(in: der)
            ?? fallbackCurveFromKeySize(der)
        guard let curve else {
            throw SwiftmikoError.authenticationFailed(
                "Cannot determine elliptic curve from EC PRIVATE KEY. " +
                "Supported curves: P-256, P-384, P-521"
            )
        }
        return try makeECKeyFromDER(der, curve: curve)
    }

    // MARK: - PKCS8 PEM (-----BEGIN PRIVATE KEY-----)

    private static func parsePKCS8(pem: String) throws -> NIOSSHPrivateKey {
        let der = try decodePEM(pem)

        // Algorithm OIDs in DER/TLV form: [tag=0x06, length, ...OID bytes]
        let ed25519OID: [UInt8] = [0x06, 0x03, 0x2b, 0x65, 0x70]
        let p256OID: [UInt8]    = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
        let p384OID: [UInt8]    = [0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22]
        let p521OID: [UInt8]    = [0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x23]
        let rsaOID: [UInt8]     = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]

        if der.contains(subsequence: ed25519OID) {
            return try parsePKCS8Ed25519(der: der)
        }
        if der.contains(subsequence: p256OID) {
            return try makeECKeyFromDER(der, curve: .p256)
        }
        if der.contains(subsequence: p384OID) {
            return try makeECKeyFromDER(der, curve: .p384)
        }
        if der.contains(subsequence: p521OID) {
            return try makeECKeyFromDER(der, curve: .p521)
        }
        if der.contains(subsequence: rsaOID) {
            throw SwiftmikoError.notImplemented(
                "RSA private keys are not supported. " +
                "Convert to Ed25519: ssh-keygen -t ed25519 -f <new_key>"
            )
        }
        throw SwiftmikoError.authenticationFailed(
            "Unrecognised algorithm OID in PKCS8 private key"
        )
    }

    private static func parsePKCS8Ed25519(der: [UInt8]) throws -> NIOSSHPrivateKey {
        // PKCS8 Ed25519 DER layout:
        //   SEQUENCE {
        //     INTEGER 0
        //     SEQUENCE { OID 1.3.101.112 }
        //     OCTET STRING {               ← outer (tag 0x04)
        //       OCTET STRING { 32 bytes }  ← inner (tag 0x04, len 0x20)
        //     }
        //   }
        // Strategy: find the OID, then scan forward for the outer OCTET STRING.
        let ed25519OID: [UInt8] = [0x06, 0x03, 0x2b, 0x65, 0x70]
        guard let oidEnd = der.firstRange(of: ed25519OID)?.upperBound else {
            throw SwiftmikoError.authenticationFailed("Ed25519 OID not found in PKCS8 DER")
        }

        var i = oidEnd
        while i + 3 < der.count {
            guard der[i] == 0x04 else { i += 1; continue }

            let (outerLen, outerLenSize) = parseDERLength(der, at: i + 1)
            let outerDataStart = i + 1 + outerLenSize
            guard outerDataStart + outerLen <= der.count else { i += 1; continue }

            // Check for inner OCTET STRING: 0x04 0x20 <32 bytes>
            if outerLen >= 34,
               der[outerDataStart] == 0x04,
               der[outerDataStart + 1] == 0x20 {
                let seed = Data(der[(outerDataStart + 2)..<(outerDataStart + 34)])
                return try wrapEd25519(seed)
            }
            // Occasionally the outer OCTET STRING itself IS the 32-byte seed
            if outerLen == 32 {
                let seed = Data(der[outerDataStart..<(outerDataStart + 32)])
                return try wrapEd25519(seed)
            }
            i += 1
        }
        throw SwiftmikoError.authenticationFailed(
            "Cannot locate Ed25519 private key seed in PKCS8 DER"
        )
    }

    // MARK: - Shared construction helpers

    private static func wrapEd25519(_ seed: Data) throws -> NIOSSHPrivateKey {
        do {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return NIOSSHPrivateKey(ed25519Key: key)
        } catch {
            throw SwiftmikoError.authenticationFailed(
                "Invalid Ed25519 seed bytes: \(error.localizedDescription)"
            )
        }
    }

    private static func makeECKeyFromDER(_ der: [UInt8], curve: ECCurve) throws -> NIOSSHPrivateKey {
        let data = Data(der)
        do {
            switch curve {
            case .p256:
                let key = try P256.Signing.PrivateKey(derRepresentation: data)
                return NIOSSHPrivateKey(p256Key: key)
            case .p384:
                let key = try P384.Signing.PrivateKey(derRepresentation: data)
                return NIOSSHPrivateKey(p384Key: key)
            case .p521:
                let key = try P521.Signing.PrivateKey(derRepresentation: data)
                return NIOSSHPrivateKey(p521Key: key)
            }
        } catch {
            throw SwiftmikoError.authenticationFailed(
                "Invalid \(curve.displayName) key DER: \(error.localizedDescription)"
            )
        }
    }

    private static func makeECKey(scalar: [UInt8], curve: ECCurve) throws -> NIOSSHPrivateKey {
        // Left-pad the scalar to the expected byte length for the curve.
        let padded = Data(leftPadding: scalar, to: curve.scalarByteCount)
        do {
            switch curve {
            case .p256:
                let key = try P256.Signing.PrivateKey(rawRepresentation: padded)
                return NIOSSHPrivateKey(p256Key: key)
            case .p384:
                let key = try P384.Signing.PrivateKey(rawRepresentation: padded)
                return NIOSSHPrivateKey(p384Key: key)
            case .p521:
                let key = try P521.Signing.PrivateKey(rawRepresentation: padded)
                return NIOSSHPrivateKey(p521Key: key)
            }
        } catch {
            throw SwiftmikoError.authenticationFailed(
                "Invalid \(curve.displayName) private scalar: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - PEM helpers

    private static func decodePEM(_ pem: String) throws -> [UInt8] {
        let b64 = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: b64) else {
            throw SwiftmikoError.authenticationFailed("Invalid base64 encoding in PEM key file")
        }
        return Array(data)
    }

    // MARK: - Curve detection

    private enum ECCurve {
        case p256, p384, p521

        var scalarByteCount: Int {
            switch self {
            case .p256: return 32
            case .p384: return 48
            case .p521: return 66
            }
        }

        var displayName: String {
            switch self {
            case .p256: return "P-256"
            case .p384: return "P-384"
            case .p521: return "P-521"
            }
        }
    }

    /// Detect named-curve OID in SEC1 or PKCS8 DER bytes.
    private static func sec1Curve(in der: [UInt8]) -> ECCurve? {
        let p256: [UInt8] = [0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
        let p384: [UInt8] = [0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22]
        let p521: [UInt8] = [0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x23]
        if der.contains(subsequence: p256) { return .p256 }
        if der.contains(subsequence: p384) { return .p384 }
        if der.contains(subsequence: p521) { return .p521 }
        return nil
    }

    /// Last-resort: infer curve from the raw key size embedded in the DER.
    private static func fallbackCurveFromKeySize(_ der: [UInt8]) -> ECCurve? {
        // SEC1 PrivateKey OCTET STRING is the 2nd field after INTEGER 1.
        // Its length hints at the curve: 32 → P256, 48 → P384, 66 → P521.
        var i = 0
        while i + 1 < der.count {
            if der[i] == 0x04 {  // OCTET STRING tag
                let (len, _) = parseDERLength(der, at: i + 1)
                switch len {
                case 32: return .p256
                case 48: return .p384
                case 66: return .p521
                default: break
                }
            }
            i += 1
        }
        return nil
    }

    // MARK: - Minimal DER length decoder

    /// Returns `(length, bytesConsumed)` for a DER length field starting at `offset`.
    private static func parseDERLength(_ bytes: [UInt8], at offset: Int) -> (Int, Int) {
        guard offset < bytes.count else { return (0, 0) }
        let first = bytes[offset]
        if first & 0x80 == 0 { return (Int(first), 1) }
        let n = Int(first & 0x7f)
        guard n > 0, offset + n < bytes.count else { return (0, 1) }
        var length = 0
        for k in 1...n { length = (length << 8) | Int(bytes[offset + k]) }
        return (length, 1 + n)
    }
}

// MARK: - KeyAuthDelegate

/// NIO user-auth delegate that offers a loaded private key for publickey auth.
///
/// @unchecked Sendable: each instance is single-use per connection attempt,
/// mutated only by NIOSSHHandler's serial calls to nextAuthenticationType(:)
/// on the channel's event loop — never shared across connections or threads.
final class KeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let nioKey: NIOSSHPrivateKey
    private var offered = false

    init(username: String, nioKey: NIOSSHPrivateKey) {
        self.username = username
        self.nioKey   = nioKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: nioKey))
            )
        )
    }
}

// MARK: - SSHBuffer: SSH wire-format reader

/// Reads SSH wire-format primitives (uint32, SSH strings, mpints) from a byte slice.
private struct SSHBuffer {
    private let bytes: [UInt8]
    private var offset: Int = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard offset + count <= bytes.count else {
            throw SwiftmikoError.authenticationFailed(
                "Truncated SSH key data (need \(count) bytes, \(bytes.count - offset) remain)"
            )
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    /// Reads a length-prefixed SSH string (4-byte big-endian length + data).
    mutating func readSSHString() throws -> [UInt8] {
        let len = Int(try readUInt32())
        return try readBytes(len)
    }

    /// Reads an SSH mpint and strips the leading sign byte (0x00) if present.
    mutating func readMPInt() throws -> [UInt8] {
        var data = try readSSHString()
        while data.first == 0x00 { data.removeFirst() }
        return data
    }
}

// MARK: - Array helpers

extension Array where Element == UInt8 {
    /// Returns the start index of the first occurrence of `subsequence`, or nil.
    func firstRange(of subsequence: [UInt8]) -> Range<Int>? {
        guard !subsequence.isEmpty, subsequence.count <= count else { return nil }
        for i in 0...(count - subsequence.count) {
            if self[i..<(i + subsequence.count)].elementsEqual(subsequence) {
                return i..<(i + subsequence.count)
            }
        }
        return nil
    }

    func contains(subsequence: [UInt8]) -> Bool {
        firstRange(of: subsequence) != nil
    }
}

// MARK: - Data helper

private extension Data {
    /// Construct `Data` from `bytes`, left-padding with 0x00 to reach `targetLength`.
    init(leftPadding bytes: [UInt8], to targetLength: Int) {
        let padding = Swift.max(0, targetLength - bytes.count)
        self = Data(repeating: 0, count: padding) + bytes
    }
}
