//===----------------------------------------------------------------------===//
//
// Fork addition (not part of upstream swift-nio-ssh): classic finite-field
// Diffie-Hellman key exchange (RFC 4253 §8, group14-sha1 / RFC 3526 §3),
// for SSH servers too old to offer ECDH or Curve25519 — e.g. classic Cisco
// IOS on hardware like a C7200. Upstream swift-nio-ssh only implements
// elliptic-curve KEX; this fills the gap using the same
// EllipticCurveKeyExchangeProtocol extension point (the wire messages for
// SSH_MSG_KEXDH_INIT/REPLY happen to share message IDs 30/31 with
// SSH_MSG_KEX_ECDH_INIT/REPLY and are encoded identically as length-prefixed
// byte strings, so KeyExchangeECDHInitMessage/KeyExchangeECDHReplyMessage
// and their wire encoding are reused as-is).
//
//===----------------------------------------------------------------------===//

import Crypto
import NIOCore
import NIOFoundationCompat

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Minimal arbitrary-precision unsigned integer

/// Just enough big-integer arithmetic to do classic Diffie-Hellman modular
/// exponentiation. Not general-purpose, not constant-time, not optimized —
/// correctness and auditability over speed, since this runs once per SSH
/// connection setup, not in a hot loop.
private struct BigUInt {
    /// Little-endian 32-bit limbs. Always normalized: no trailing (high-order)
    /// zero limbs, except that zero itself is represented as an empty array.
    var limbs: [UInt32]

    private init(rawLimbs limbs: [UInt32]) {
        self.limbs = limbs
    }

    init(limbs: [UInt32]) {
        self.limbs = limbs
        self.normalize()
    }

    init(_ value: UInt32) {
        self.limbs = value == 0 ? [] : [value]
    }

    /// Parses an unsigned big-endian byte string. Any leading zero bytes
    /// (e.g. the SSH mpint sign-safety padding byte) are harmless here —
    /// they just contribute leading zero limbs that get normalized away.
    init(bigEndianBytes bytes: some Sequence<UInt8>) {
        let bytes = Array(bytes)
        var limbs = [UInt32]()
        var i = bytes.count
        while i > 0 {
            let start = Swift.max(0, i - 4)
            var limb: UInt32 = 0
            for j in start..<i {
                limb = (limb << 8) | UInt32(bytes[j])
            }
            limbs.append(limb)
            i = start
        }
        self.limbs = limbs
        self.normalize()
    }

    /// Parses a hex string (no separators, no "0x" prefix).
    init(hexString: String) {
        var bytes = [UInt8]()
        var chars = Array(hexString)
        if chars.count % 2 != 0 {
            chars.insert("0", at: 0)
        }
        var i = 0
        while i < chars.count {
            let byteString = String(chars[i]) + String(chars[i + 1])
            bytes.append(UInt8(byteString, radix: 16)!)
            i += 2
        }
        self.init(bigEndianBytes: bytes)
    }

    private mutating func normalize() {
        while let last = limbs.last, last == 0 {
            limbs.removeLast()
        }
    }

    var isZero: Bool {
        limbs.isEmpty
    }

    /// Position of the highest set bit, plus one. Zero for the value zero.
    var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - Int(top.leadingZeroBitCount))
    }

    func testBit(_ i: Int) -> Bool {
        let limbIndex = i / 32
        guard limbIndex < limbs.count else { return false }
        return (limbs[limbIndex] >> (i % 32)) & 1 == 1
    }

    /// Unsigned big-endian bytes, minimal length (at least one byte).
    func bigEndianBytes() -> [UInt8] {
        if isZero { return [0] }
        var bytes = [UInt8]()
        for limb in limbs.reversed() {
            bytes.append(UInt8((limb >> 24) & 0xFF))
            bytes.append(UInt8((limb >> 16) & 0xFF))
            bytes.append(UInt8((limb >> 8) & 0xFF))
            bytes.append(UInt8(limb & 0xFF))
        }
        while bytes.count > 1 && bytes[0] == 0 {
            bytes.removeFirst()
        }
        return bytes
    }

    /// Bytes formatted per the SSH mpint convention (RFC 4251 §5): unsigned
    /// big-endian magnitude, with a leading zero byte inserted if the
    /// high bit of the first byte would otherwise look like a sign bit.
    /// This is the content that goes inside an SSH "string" framing — the
    /// caller is responsible for the length prefix (writeSSHString /
    /// writeCompositeSSHString already do that).
    func mpintContentBytes() -> [UInt8] {
        var bytes = bigEndianBytes()
        if bytes[0] & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return bytes
    }

    static func < (a: BigUInt, b: BigUInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] {
            return a.limbs[i] < b.limbs[i]
        }
        return false
    }

    static func <= (a: BigUInt, b: BigUInt) -> Bool {
        a < b || a == b
    }

    static func == (a: BigUInt, b: BigUInt) -> Bool {
        a.limbs == b.limbs
    }

    /// Assumes a >= b.
    static func - (a: BigUInt, b: BigUInt) -> BigUInt {
        var result = [UInt32]()
        result.reserveCapacity(a.limbs.count)
        var borrow: Int64 = 0
        for i in 0..<a.limbs.count {
            let bi = i < b.limbs.count ? Int64(b.limbs[i]) : 0
            var diff = Int64(a.limbs[i]) - bi - borrow
            if diff < 0 {
                diff += 0x1_0000_0000
                borrow = 1
            } else {
                borrow = 0
            }
            result.append(UInt32(diff))
        }
        return BigUInt(limbs: result)
    }

    static func * (a: BigUInt, b: BigUInt) -> BigUInt {
        if a.isZero || b.isZero { return BigUInt(0) }
        var result = [UInt64](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            let ai = UInt64(a.limbs[i])
            if ai == 0 { continue }
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                let product = ai * UInt64(b.limbs[j]) + result[i + j] + carry
                result[i + j] = product & 0xFFFF_FFFF
                carry = product >> 32
            }
            var k = i + b.limbs.count
            while carry > 0 {
                let sum = result[k] + carry
                result[k] = sum & 0xFFFF_FFFF
                carry = sum >> 32
                k += 1
            }
        }
        return BigUInt(limbs: result.map { UInt32($0) })
    }

    /// Drops the low `n` limbs (i.e. divides by `2^(32n)`).
    private func limbsDroppingLow(_ n: Int) -> [UInt32] {
        n >= limbs.count ? [] : Array(limbs[n...])
    }

    /// Keeps only the low `n` limbs (i.e. reduces mod `2^(32n)`).
    private func limbsTruncated(to n: Int) -> [UInt32] {
        Array(limbs.prefix(n))
    }

    /// Barrett reduction: computes `self mod m`, for `self < b^(2k)` where
    /// `b = 2^32` and `k` is `m`'s limb count. `mu` must be
    /// `floor(b^(2k) / m)`, precomputed once for the fixed modulus this
    /// exchange uses (see `DiffieHellmanGroup14.mu`).
    ///
    /// This replaces an earlier bit-serial shift-and-subtract reduction
    /// that, while simple to audit, took ~10 seconds per call in a Debug
    /// build — long enough that a real SSH peer's handshake timeout fired
    /// before this side ever sent its reply (confirmed against a real
    /// Cisco IOS device via `debug ip ssh`: an ~8-9s gap between the peer
    /// announcing it was waiting for our message and that message actually
    /// arriving). Barrett reduction turns each reduction into two
    /// multiplications and a short (0-2 iteration) correction loop instead
    /// of an O(bitWidth) loop, which is the dominant cost in a modPow.
    fileprivate func barrettReduced(modulus m: BigUInt, mu: BigUInt, k: Int) -> BigUInt {
        let q1 = BigUInt(limbs: self.limbsDroppingLow(k - 1))
        let q2 = q1 * mu
        let q3 = BigUInt(limbs: q2.limbsDroppingLow(k + 1))

        let width = k + 1
        var r1 = self.limbsTruncated(to: width)
        if r1.count < width {
            r1.append(contentsOf: repeatElement(0, count: width - r1.count))
        }
        var r2 = (q3 * m).limbsTruncated(to: width)
        if r2.count < width {
            r2.append(contentsOf: repeatElement(0, count: width - r2.count))
        }

        // r1 - r2, wrapping mod b^width (i.e. any final borrow is simply
        // discarded) — this is exactly "(self mod b^width) - (q3*m mod
        // b^width), mod b^width" as Barrett's algorithm requires.
        var rLimbs = [UInt32](repeating: 0, count: width)
        var borrow: Int64 = 0
        for i in 0..<width {
            var diff = Int64(r1[i]) - Int64(r2[i]) - borrow
            if diff < 0 {
                diff += 0x1_0000_0000
                borrow = 1
            } else {
                borrow = 0
            }
            rLimbs[i] = UInt32(diff)
        }

        var r = BigUInt(limbs: rLimbs)
        // Barrett's error bound guarantees r is at most a couple of
        // multiples of m too big; a handful of plain subtractions cleans
        // that up cheaply (this is the only part of the old bit-serial
        // approach still in the hot path, but it now runs 0-2 times
        // instead of ~2048).
        while m <= r {
            r = r - m
        }
        return r
    }

    static func mulmod(_ a: BigUInt, _ b: BigUInt, _ m: BigUInt, mu: BigUInt, k: Int) -> BigUInt {
        (a * b).barrettReduced(modulus: m, mu: mu, k: k)
    }

    /// Modular exponentiation via left-to-right binary square-and-multiply.
    /// `mu`/`k` are the Barrett reduction constant/limb-count for `modulus`.
    static func modPow(base: BigUInt, exponent: BigUInt, modulus: BigUInt, mu: BigUInt, k: Int) -> BigUInt {
        var result = BigUInt(1)
        let base = base < modulus ? base : base.barrettReduced(modulus: modulus, mu: mu, k: k)
        var bit = exponent.bitWidth - 1
        while bit >= 0 {
            result = mulmod(result, result, modulus, mu: mu, k: k)
            if exponent.testBit(bit) {
                result = mulmod(result, base, modulus, mu: mu, k: k)
            }
            bit -= 1
        }
        return result
    }
}

extension BigUInt: Equatable {}

// MARK: - RFC 3526 §3 2048-bit MODP Group (Group 14)

private struct DiffieHellmanGroup14 {
    let prime: BigUInt
    let generator: BigUInt
    /// Barrett reduction constant for `prime`: `floor(2^(64*k) / prime)`,
    /// where `k` is `prime`'s limb count (64, for a 2048-bit modulus with
    /// 32-bit limbs). Computed once, offline (Python's arbitrary-precision
    /// `int`), and hardcoded here rather than derived at runtime, since
    /// deriving it needs the same kind of slow division this constant
    /// exists to avoid — but it only ever needs computing once for a
    /// modulus that never changes.
    let mu: BigUInt
    let k: Int

    static let shared: DiffieHellmanGroup14 = {
        // RFC 3526 §3, transcribed line-for-line so it stays checkable
        // against the RFC text (each line is one of the RFC's published
        // 48-hex-digit groups, last line 32 digits).
        let primeHex =
            "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1"
            + "29024E088A67CC74020BBEA63B139B22514A08798E3404DD"
            + "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245"
            + "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
            + "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D"
            + "C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F"
            + "83655D23DCA3AD961C62F356208552BB9ED529077096966D"
            + "670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
            + "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9"
            + "DE2BCBF6955817183995497CEA956AE515D2261898FA0510"
            + "15728E5A8AACAA68FFFFFFFFFFFFFFFF"
        let prime = BigUInt(hexString: primeHex)
        // Sanity check against transcription errors: the group 14 prime is
        // exactly 2048 bits and odd.
        precondition(prime.bitWidth == 2048, "diffie-hellman-group14-sha1 prime is malformed")
        precondition(prime.testBit(0), "diffie-hellman-group14-sha1 prime must be odd")

        // floor(2^4096 / prime), computed via:
        //   python3 -c "p = int('<primeHex>', 16); print(format((1 << 4096) // p, '0512X'))"
        let muHex =
            "1000000000000000036F0255DDE973DCB4703CE7E2E815197A"
            + "6DB0F588448B61164CFCAC5F1872E51B1F9FBB5BF16FBE7968"
            + "9FC0903A801E3D4802FB8D329550DC8C9D3D922EECE9A5475D"
            + "B33DB7B83BB5C0E13D168049BBC86C5817647B088D17AA5CC4"
            + "0E02035588EDB2DE18993413719FC258D79BC217AC4B8739CB"
            + "EA038AAA88D0D2F78A77A8A6FC7FAA8B2BDCA9BE7502D2F5F6"
            + "A7B65F5E4F07AB8B286E41115F024A6E976BD2BCE3E5190B89"
            + "1ABBF2331E9C94DE91FBE8574370494A354EAC9BE0B31EB318"
            + "540E4069D556E9DD09D5D89D7DE4A75C88BB49316C106E4E01"
            + "4B636E60FEBC292E6249105F5B195FE906EEF7D26C90A17477"
            + "122CE125FB664"
        let mu = BigUInt(hexString: muHex)
        // mu must satisfy mu*prime <= 2^4096 < (mu+1)*prime.
        precondition(mu.bitWidth == 2049, "group14 Barrett constant is malformed")

        return DiffieHellmanGroup14(prime: prime, generator: BigUInt(2), mu: mu, k: 64)
    }()
}

// MARK: - Classic Diffie-Hellman key exchange

/// Implements RFC 4253 §8's classic (finite-field) Diffie-Hellman key
/// exchange, restricted to group14-sha1: the fixed 2048-bit MODP group
/// from RFC 3526 §3, with a SHA-1 exchange hash. This is the only classic
/// DH variant this fork adds — diffie-hellman-group1-sha1 (768-bit, broken)
/// is deliberately not implemented, and diffie-hellman-group-exchange-sha1
/// (server-negotiated group size) adds an extra round trip for no security
/// benefit over the fixed group14 group.
struct ClassicDiffieHellmanKeyExchange: EllipticCurveKeyExchangeProtocol {
    private var previousSessionIdentifier: ByteBuffer?
    private var ourRole: SSHConnectionRole
    private var privateExponent: BigUInt
    private var ourPublicValue: BigUInt
    private var theirPublicValue: BigUInt?

    init(ourRole: SSHConnectionRole, previousSessionIdentifier: ByteBuffer?) {
        self.ourRole = ourRole
        self.previousSessionIdentifier = previousSessionIdentifier
        self.privateExponent = Self.generatePrivateExponent()
        self.ourPublicValue = BigUInt.modPow(
            base: DiffieHellmanGroup14.shared.generator,
            exponent: self.privateExponent,
            modulus: DiffieHellmanGroup14.shared.prime,
            mu: DiffieHellmanGroup14.shared.mu,
            k: DiffieHellmanGroup14.shared.k
        )
    }

    static var keyExchangeAlgorithmNames: [Substring] {
        ["diffie-hellman-group14-sha1"]
    }

    /// A private exponent this size gives the conventional ~2x security
    /// margin used for a 2048-bit MODP group (matching common practice in
    /// other SSH implementations), and keeps modular exponentiation cheap:
    /// the number of squarings in modPow is bounded by the exponent's bit
    /// length, not the modulus's.
    private static func generatePrivateExponent() -> BigUInt {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { BigUInt(bigEndianBytes: Array($0)) }
    }

    func initiateKeyExchangeClientSide(allocator: ByteBufferAllocator) -> SSHMessage.KeyExchangeECDHInitMessage {
        precondition(self.ourRole.isClient, "Only clients may initiate the client side key exchange!")

        var buffer = allocator.buffer(capacity: 256)
        buffer.writeBytes(self.ourPublicValue.mpintContentBytes())
        return .init(publicKey: buffer)
    }

    mutating func completeKeyExchangeServerSide(
        clientKeyExchangeMessage message: SSHMessage.KeyExchangeECDHInitMessage,
        serverHostKey: NIOSSHPrivateKey,
        initialExchangeBytes: inout ByteBuffer,
        allocator: ByteBufferAllocator,
        expectedKeySizes: ExpectedKeySizes
    ) throws -> (KeyExchangeResult, SSHMessage.KeyExchangeECDHReplyMessage) {
        precondition(self.ourRole.isServer, "Only servers may receive a client key exchange packet!")

        let kexResult = try self.finalizeKeyExchange(
            theirPublicValueBytes: message.publicKey,
            initialExchangeBytes: &initialExchangeBytes,
            serverHostKey: serverHostKey.publicKey,
            allocator: allocator,
            expectedKeySizes: expectedKeySizes
        )

        let exchangeHashSignature = try serverHostKey.sign(digest: kexResult.exchangeHash)

        var publicKeyBytes = allocator.buffer(capacity: 256)
        publicKeyBytes.writeBytes(self.ourPublicValue.mpintContentBytes())

        let responseMessage = SSHMessage.KeyExchangeECDHReplyMessage(
            hostKey: serverHostKey.publicKey,
            publicKey: publicKeyBytes,
            signature: exchangeHashSignature
        )

        return (KeyExchangeResult(kexResult), responseMessage)
    }

    mutating func receiveServerKeyExchangePayload(
        serverKeyExchangeMessage message: SSHMessage.KeyExchangeECDHReplyMessage,
        initialExchangeBytes: inout ByteBuffer,
        allocator: ByteBufferAllocator,
        expectedKeySizes: ExpectedKeySizes
    ) throws -> KeyExchangeResult {
        precondition(self.ourRole.isClient, "Only clients may receive a server key exchange packet!")

        let kexResult = try self.finalizeKeyExchange(
            theirPublicValueBytes: message.publicKey,
            initialExchangeBytes: &initialExchangeBytes,
            serverHostKey: message.hostKey,
            allocator: allocator,
            expectedKeySizes: expectedKeySizes
        )

        guard message.hostKey.isValidSignature(message.signature, for: kexResult.exchangeHash) else {
            throw NIOSSHError.invalidExchangeHashSignature
        }

        return KeyExchangeResult(kexResult)
    }

    private mutating func finalizeKeyExchange(
        theirPublicValueBytes: ByteBuffer,
        initialExchangeBytes: inout ByteBuffer,
        serverHostKey: NIOSSHPublicKey,
        allocator: ByteBufferAllocator,
        expectedKeySizes: ExpectedKeySizes
    ) throws -> ClassicDHKeyExchangeResult {
        let theirValue = BigUInt(bigEndianBytes: theirPublicValueBytes.readableBytesView)

        // RFC 2631 §2.1.5-style range check: reject the trivial/degenerate
        // values 0, 1, and p-1, which would let a malicious peer force a
        // predictable shared secret (small-subgroup-style confinement).
        let prime = DiffieHellmanGroup14.shared.prime
        guard theirValue < prime, BigUInt(1) < theirValue, theirValue != prime - BigUInt(1) else {
            throw NIOSSHError.invalidSSHMessage(
                reason: "diffie-hellman-group14-sha1 peer public value out of range"
            )
        }
        self.theirPublicValue = theirValue

        let sharedSecret = BigUInt.modPow(
            base: theirValue,
            exponent: self.privateExponent,
            modulus: prime,
            mu: DiffieHellmanGroup14.shared.mu,
            k: DiffieHellmanGroup14.shared.k
        )

        initialExchangeBytes.writeCompositeSSHString { $0.writeSSHHostKey(serverHostKey) }

        switch self.ourRole {
        case .client:
            initialExchangeBytes.writeCompositeSSHString { $0.writeBytes(self.ourPublicValue.mpintContentBytes()) }
            initialExchangeBytes.writeCompositeSSHString { $0.writeBytes(theirValue.mpintContentBytes()) }
        case .server:
            initialExchangeBytes.writeCompositeSSHString { $0.writeBytes(theirValue.mpintContentBytes()) }
            initialExchangeBytes.writeCompositeSSHString { $0.writeBytes(self.ourPublicValue.mpintContentBytes()) }
        }

        var hasher = Insecure.SHA1()
        hasher.update(data: initialExchangeBytes.readableBytesView)

        var secretBuffer = allocator.buffer(capacity: 264)
        secretBuffer.writeCompositeSSHString { $0.writeBytes(sharedSecret.mpintContentBytes()) }
        hasher.update(data: secretBuffer.readableBytesView)

        let exchangeHash = hasher.finalize()

        let sessionID: ByteBuffer
        if let previousSessionIdentifier = self.previousSessionIdentifier {
            sessionID = previousSessionIdentifier
        } else {
            var hashBytes = allocator.buffer(capacity: Insecure.SHA1.Digest.byteCount)
            hashBytes.writeContiguousBytes(exchangeHash)
            sessionID = hashBytes
        }

        let keys = self.generateKeys(
            sharedSecret: sharedSecret,
            exchangeHash: exchangeHash,
            sessionID: sessionID,
            expectedKeySizes: expectedKeySizes
        )

        return ClassicDHKeyExchangeResult(sessionID: sessionID, exchangeHash: exchangeHash, keys: keys)
    }

    /// Mirrors EllipticCurveKeyExchange.generateKeys, substituting a plain
    /// mpint-encoded BigUInt for CryptoKit's ECDH-only SharedSecret type.
    private func generateKeys(
        sharedSecret: BigUInt,
        exchangeHash: Insecure.SHA1.Digest,
        sessionID: ByteBuffer,
        expectedKeySizes: ExpectedKeySizes
    ) -> NIOSSHSessionKeys {
        var baseHasher = Insecure.SHA1()
        let secretBytes = sharedSecret.mpintContentBytes()
        var lengthPrefix = [UInt8](repeating: 0, count: 4)
        let length = UInt32(secretBytes.count)
        lengthPrefix[0] = UInt8((length >> 24) & 0xFF)
        lengthPrefix[1] = UInt8((length >> 16) & 0xFF)
        lengthPrefix[2] = UInt8((length >> 8) & 0xFF)
        lengthPrefix[3] = UInt8(length & 0xFF)
        baseHasher.update(data: lengthPrefix)
        baseHasher.update(data: secretBytes)
        exchangeHash.withUnsafeBytes { hashPtr in
            baseHasher.update(bufferPointer: hashPtr)
        }

        switch self.ourRole {
        case .client:
            return NIOSSHSessionKeys(
                initialInboundIV: self.generateHash(baseHasher: baseHasher, discriminator: "B", sessionID: sessionID, length: expectedKeySizes.ivSize),
                initialOutboundIV: self.generateHash(baseHasher: baseHasher, discriminator: "A", sessionID: sessionID, length: expectedKeySizes.ivSize),
                inboundEncryptionKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "D", sessionID: sessionID, length: expectedKeySizes.encryptionKeySize),
                outboundEncryptionKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "C", sessionID: sessionID, length: expectedKeySizes.encryptionKeySize),
                inboundMACKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "F", sessionID: sessionID, length: expectedKeySizes.macKeySize),
                outboundMACKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "E", sessionID: sessionID, length: expectedKeySizes.macKeySize)
            )
        case .server:
            return NIOSSHSessionKeys(
                initialInboundIV: self.generateHash(baseHasher: baseHasher, discriminator: "A", sessionID: sessionID, length: expectedKeySizes.ivSize),
                initialOutboundIV: self.generateHash(baseHasher: baseHasher, discriminator: "B", sessionID: sessionID, length: expectedKeySizes.ivSize),
                inboundEncryptionKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "C", sessionID: sessionID, length: expectedKeySizes.encryptionKeySize),
                outboundEncryptionKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "D", sessionID: sessionID, length: expectedKeySizes.encryptionKeySize),
                inboundMACKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "E", sessionID: sessionID, length: expectedKeySizes.macKeySize),
                outboundMACKey: self.generateSymmetricKey(baseHasher: baseHasher, discriminator: "F", sessionID: sessionID, length: expectedKeySizes.macKeySize)
            )
        }
    }

    private func generateHash(
        baseHasher: Insecure.SHA1,
        discriminator: Unicode.Scalar,
        sessionID: ByteBuffer,
        length: Int
    ) -> [UInt8] {
        assert(length <= Insecure.SHA1.Digest.byteCount)
        var localHasher = baseHasher
        localHasher.update(data: [UInt8(discriminator.value)])
        localHasher.update(data: sessionID.readableBytesView)
        return Array(localHasher.finalize().prefix(length))
    }

    private func generateSymmetricKey(
        baseHasher: Insecure.SHA1,
        discriminator: Unicode.Scalar,
        sessionID: ByteBuffer,
        length: Int
    ) -> SymmetricKey {
        SymmetricKey(data: self.generateHash(baseHasher: baseHasher, discriminator: discriminator, sessionID: sessionID, length: length))
    }
}

private struct ClassicDHKeyExchangeResult {
    var sessionID: ByteBuffer
    var exchangeHash: Insecure.SHA1.Digest
    var keys: NIOSSHSessionKeys
}

extension KeyExchangeResult {
    fileprivate init(_ innerResult: ClassicDHKeyExchangeResult) {
        self.keys = innerResult.keys
        self.sessionID = innerResult.sessionID
    }
}
