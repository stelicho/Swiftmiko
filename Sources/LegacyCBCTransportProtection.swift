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
//  LegacyCBCTransportProtection.swift
//  Swiftmiko
//
//  Opt-in AES-CBC transport protection for SSH servers that predate
//  RFC 5647 / OpenSSH AES-GCM (swift-nio-ssh implements only AES-GCM).
//
//  CBC-mode SSH ciphers have known weaknesses (CVE-2008-5161-style
//  plaintext recovery) and are deliberately NOT bundled by swift-nio-ssh.
//  This exists purely to talk to old lab/EOL gear (e.g. Cisco C7200 IOS
//  images) that never implemented anything newer. It is never enabled by
//  default — callers must opt in via ConnectionProfile.allowLegacyCiphers.
//

import CCommonCryptoShim
import Crypto
import Foundation
import NIOCore
import NIOSSH

// MARK: - CommonCrypto CBC wrapper

/// Thin, stateful wrapper around a CommonCrypto `CCCryptorRef` running in
/// CBC mode with no padding. SSH's traditional CBC framing chains the IV
/// continuously across the whole connection (not per-packet), which is
/// exactly what a single long-lived `CCCryptorRef` gives us for free: each
/// call to `update` continues the chain from the ciphertext of the
/// previous call.
private final class CBCCryptor {
    private var ref: CCCryptorRef?

    init(operation: CCOperation, key: [UInt8], iv: [UInt8]) throws {
        var ref: CCCryptorRef?
        let status = CCCryptorCreateWithMode(
            operation,
            CCMode(kCCModeCBC),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            iv,
            key,
            key.count,
            nil,
            0,
            0,
            CCModeOptions(0),
            &ref
        )
        guard status == kCCSuccess, let ref else {
            throw SwiftmikoError.connectionFailed("Failed to initialize AES-CBC cryptor (CommonCrypto status \(status))")
        }
        self.ref = ref
    }

    deinit {
        if let ref {
            CCCryptorRelease(ref)
        }
    }

    /// Encrypts or decrypts `input` in place, continuing this cryptor's CBC chain.
    /// `input.count` must be a non-zero multiple of the AES block size (16).
    func update(_ input: inout [UInt8]) throws {
        guard let ref else {
            throw SwiftmikoError.connectionFailed("AES-CBC cryptor used after release")
        }
        var output = [UInt8](repeating: 0, count: input.count)
        var moved = 0
        let status = CCCryptorUpdate(ref, input, input.count, &output, output.count, &moved)
        guard status == kCCSuccess, moved == input.count else {
            throw SwiftmikoError.connectionFailed("AES-CBC operation failed (CommonCrypto status \(status))")
        }
        input = output
    }
}

// MARK: - MAC kind

/// SSH negotiates the MAC as part of the cipher name in swift-nio-ssh's
/// model (see NIOSSHTransportProtection's documentation), so each concrete
/// leaf class below pins exactly one of these.
internal enum LegacyMACKind: Sendable {
    case hmacSHA1
    case hmacSHA256

    var digestByteCount: Int {
        switch self {
        case .hmacSHA1: return 20
        case .hmacSHA256: return 32
        }
    }
}

// MARK: - CBCTransportProtection base class

/// Base implementation shared by the AES-128-CBC leaf classes below. Modeled
/// on swift-nio-ssh's own `AESGCMTransportProtection`, but CBC is not an AEAD
/// construction: encryption and integrity protection are separate steps, and
/// (per RFC 4253 §6.4) the MAC covers the sequence number plus the *entire*
/// unencrypted packet, including the length field.
public class CBCTransportProtection {
    private var outboundCryptor: CBCCryptor
    private var inboundCryptor: CBCCryptor
    private var outboundMACKey: SymmetricKey
    private var inboundMACKey: SymmetricKey

    public class var cipherName: String {
        fatalError("Must override cipher name")
    }

    public class var macName: String? {
        fatalError("Must override MAC name")
    }

    public class var keySizes: ExpectedKeySizes {
        fatalError("Must override key size")
    }

    class var macKind: LegacyMACKind {
        fatalError("Must override MAC kind")
    }

    public required init(initialKeys: NIOSSHSessionKeys) throws {
        guard initialKeys.outboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8,
            initialKeys.inboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8,
            initialKeys.outboundMACKey.bitCount == Self.keySizes.macKeySize * 8,
            initialKeys.inboundMACKey.bitCount == Self.keySizes.macKeySize * 8
        else {
            throw SwiftmikoError.connectionFailed("Invalid key size negotiated for \(Self.cipherName)")
        }
        guard initialKeys.initialOutboundIV.count == Self.cipherBlockSize,
            initialKeys.initialInboundIV.count == Self.cipherBlockSize
        else {
            throw SwiftmikoError.connectionFailed("Invalid IV size negotiated for \(Self.cipherName)")
        }

        self.outboundCryptor = try CBCCryptor(
            operation: CCOperation(kCCEncrypt),
            key: initialKeys.outboundEncryptionKey.withUnsafeBytes { Array($0) },
            iv: initialKeys.initialOutboundIV
        )
        self.inboundCryptor = try CBCCryptor(
            operation: CCOperation(kCCDecrypt),
            key: initialKeys.inboundEncryptionKey.withUnsafeBytes { Array($0) },
            iv: initialKeys.initialInboundIV
        )
        self.outboundMACKey = initialKeys.outboundMACKey
        self.inboundMACKey = initialKeys.inboundMACKey
    }
}

extension CBCTransportProtection: NIOSSHTransportProtection {
    public static var cipherBlockSize: Int {
        16
    }

    public var macBytes: Int {
        Self.macKind.digestByteCount
    }

    /// Classic SSH CBC (unlike the OpenSSH AES-GCM modes) encrypts the
    /// length field as part of the first cipher block.
    public var lengthEncrypted: Bool {
        true
    }

    public func updateKeys(_ newKeys: NIOSSHSessionKeys) throws {
        guard newKeys.outboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8,
            newKeys.inboundEncryptionKey.bitCount == Self.keySizes.encryptionKeySize * 8
        else {
            throw SwiftmikoError.connectionFailed("Invalid key size negotiated for \(Self.cipherName)")
        }

        // A rekey resets the CBC chain, which is correct: the new IVs are
        // freshly derived specifically so the cipher state starts clean.
        self.outboundCryptor = try CBCCryptor(
            operation: CCOperation(kCCEncrypt),
            key: newKeys.outboundEncryptionKey.withUnsafeBytes { Array($0) },
            iv: newKeys.initialOutboundIV
        )
        self.inboundCryptor = try CBCCryptor(
            operation: CCOperation(kCCDecrypt),
            key: newKeys.inboundEncryptionKey.withUnsafeBytes { Array($0) },
            iv: newKeys.initialInboundIV
        )
        self.outboundMACKey = newKeys.outboundMACKey
        self.inboundMACKey = newKeys.inboundMACKey
    }

    public func decryptFirstBlock(_ source: inout ByteBuffer) throws {
        guard var block = source.getBytes(at: source.readerIndex, length: Self.cipherBlockSize) else {
            throw SwiftmikoError.connectionFailed("Truncated SSH packet header")
        }
        try self.inboundCryptor.update(&block)
        source.setBytes(block, at: source.readerIndex)
    }

    public func decryptAndVerifyRemainingPacket(_ source: inout ByteBuffer, sequenceNumber: UInt32) throws -> ByteBuffer {
        let blockSize = Self.cipherBlockSize
        let macLen = self.macBytes

        guard source.readableBytes > macLen else {
            throw SwiftmikoError.connectionFailed("SSH packet too short for CBC decryption")
        }
        let cipherLength = source.readableBytes - macLen
        guard cipherLength >= blockSize, cipherLength % blockSize == 0 else {
            throw SwiftmikoError.connectionFailed("Invalid CBC ciphertext length")
        }

        // The first block was already decrypted in place by decryptFirstBlock,
        // via the shared backing storage this slice was taken from.
        guard var plaintext = source.readBytes(length: blockSize) else {
            throw SwiftmikoError.connectionFailed("Truncated SSH packet")
        }
        let remainingLength = cipherLength - blockSize
        if remainingLength > 0 {
            guard var remainingCiphertext = source.readBytes(length: remainingLength) else {
                throw SwiftmikoError.connectionFailed("Truncated SSH packet")
            }
            try self.inboundCryptor.update(&remainingCiphertext)
            plaintext.append(contentsOf: remainingCiphertext)
        }

        guard let receivedMAC = source.readBytes(length: macLen) else {
            throw SwiftmikoError.connectionFailed("Truncated SSH packet")
        }
        // `source` is now fully drained, matching what SSHPacketParser expects.

        var authenticated = [UInt8]()
        authenticated.reserveCapacity(4 + plaintext.count)
        withUnsafeBytes(of: sequenceNumber.bigEndian) { authenticated.append(contentsOf: $0) }
        authenticated.append(contentsOf: plaintext)

        guard Self.macKind.isValid(receivedMAC, authenticating: authenticated, using: self.inboundMACKey) else {
            throw SwiftmikoError.connectionFailed(
                "SSH packet failed MAC verification for \(Self.cipherName)/\(Self.macName ?? "?") — possible tampering, or a cipher/MAC mismatch with the peer"
            )
        }

        // plaintext = packet_length(4) || padding_length(1) || payload || padding
        guard plaintext.count >= 5 else {
            throw SwiftmikoError.connectionFailed("SSH packet shorter than the minimum CBC frame")
        }
        let paddingLength = Int(plaintext[4])
        let payloadStart = 5
        let payloadEnd = plaintext.count - paddingLength
        guard paddingLength >= 4, payloadEnd >= payloadStart else {
            throw SwiftmikoError.connectionFailed("SSH packet had invalid padding")
        }

        var result = ByteBufferAllocator().buffer(capacity: payloadEnd - payloadStart)
        result.writeBytes(plaintext[payloadStart..<payloadEnd])
        return result
    }

    public func encryptPacket(_ destination: inout ByteBuffer, sequenceNumber: UInt32) throws {
        let plainLength = destination.readableBytes
        guard plainLength >= Self.cipherBlockSize, plainLength % Self.cipherBlockSize == 0 else {
            throw SwiftmikoError.connectionFailed("CBC plaintext packet is not a multiple of the block size")
        }
        guard var plaintext = destination.getBytes(at: destination.readerIndex, length: plainLength) else {
            throw SwiftmikoError.connectionFailed("Failed to read outbound SSH packet for CBC encryption")
        }

        var authenticated = [UInt8]()
        authenticated.reserveCapacity(4 + plaintext.count)
        withUnsafeBytes(of: sequenceNumber.bigEndian) { authenticated.append(contentsOf: $0) }
        authenticated.append(contentsOf: plaintext)
        let mac = Self.macKind.authenticationCode(authenticating: authenticated, using: self.outboundMACKey)

        try self.outboundCryptor.update(&plaintext)

        // Overwrite the plaintext in place with the ciphertext (same length,
        // same offset), then append the MAC after it. This mirrors how
        // AESGCMTransportProtection appends its tag: writerIndex is
        // unaffected by the setBytes call, so writeBytes lands right after
        // the newly-written ciphertext, not after stale plaintext.
        destination.setBytes(plaintext, at: destination.readerIndex)
        destination.writeBytes(mac)
    }
}

extension LegacyMACKind {
    fileprivate func authenticationCode(authenticating data: [UInt8], using key: SymmetricKey) -> [UInt8] {
        switch self {
        case .hmacSHA1:
            return Array(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: key))
        case .hmacSHA256:
            return Array(HMAC<SHA256>.authenticationCode(for: data, using: key))
        }
    }

    fileprivate func isValid(_ mac: [UInt8], authenticating data: [UInt8], using key: SymmetricKey) -> Bool {
        switch self {
        case .hmacSHA1:
            return HMAC<Insecure.SHA1>.isValidAuthenticationCode(mac, authenticating: data, using: key)
        case .hmacSHA256:
            return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: key)
        }
    }
}

// MARK: - Leaf schemes

/// AES-128-CBC paired with HMAC-SHA1 — the pairing most old Cisco IOS SSH
/// servers (e.g. classic C7200 images) actually implement.
public final class AES128CBCHMACSHA1TransportProtection: CBCTransportProtection, _NIOSSHSendableMetatype {
    public override static var cipherName: String {
        "aes128-cbc"
    }

    public override static var macName: String? {
        "hmac-sha1"
    }

    public override static var keySizes: ExpectedKeySizes {
        .init(ivSize: 16, encryptionKeySize: 16, macKeySize: 20)
    }

    override class var macKind: LegacyMACKind {
        .hmacSHA1
    }
}

/// AES-128-CBC paired with HMAC-SHA2-256, for the somewhat newer legacy
/// devices that support a stronger MAC but still lack AES-GCM.
public final class AES128CBCHMACSHA256TransportProtection: CBCTransportProtection, _NIOSSHSendableMetatype {
    public override static var cipherName: String {
        "aes128-cbc"
    }

    public override static var macName: String? {
        "hmac-sha2-256"
    }

    public override static var keySizes: ExpectedKeySizes {
        .init(ivSize: 16, encryptionKeySize: 16, macKeySize: 32)
    }

    override class var macKind: LegacyMACKind {
        .hmacSHA256
    }
}

// MARK: - Opt-in scheme list

public enum LegacyTransportProtection {
    /// swift-nio-ssh's default (secure) AES-GCM schemes, plus the legacy
    /// AES-CBC schemes above appended at lower priority — so a peer that
    /// supports GCM still gets it, and CBC is only used as a fallback.
    ///
    /// Never wired in by default. Only used when
    /// `ConnectionProfile.allowLegacyCiphers` is explicitly set to `true`.
    public static let schemesIncludingLegacyCBC: [NIOSSHTransportProtection.Type] =
        (Constants.bundledTransportProtectionSchemes
            + [AES128CBCHMACSHA1TransportProtection.self, AES128CBCHMACSHA256TransportProtection.self])
        .map { $0 }
}
