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
//  BCryptPBKDF.swift
//  Swiftmiko
//
//  OpenSSH's bcrypt_pbkdf — the key-derivation function used to turn a
//  passphrase into a decryption key/IV for a passphrase-protected
//  OpenSSH-format private key. This is NOT the crypt(3) password-hash
//  "bcrypt" format; it's a distinct PBKDF built on the same Blowfish
//  core, with its own magic string and output-mixing scheme.
//
//  Ported line-for-line from OpenBSD's lib/libutil/bcrypt_pbkdf.c,
//  fetched directly from
//  https://raw.githubusercontent.com/openbsd/src/master/lib/libutil/bcrypt_pbkdf.c
//  rather than transcribed from memory. Cross-validated against the
//  real `bcrypt` Python package's bcrypt.kdf(...) (itself a wrapper
//  around the same reference algorithm) for multiple
//  password/salt/rounds/keyLength combinations before being trusted —
//  see BCryptPBKDFTests.swift.
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum BCryptPBKDF {
    private static let magicCiphertext: [UInt8] = Array("OxychromaticBlowfishSwatDynamite".utf8)
    private static let hashSize = 32  // BCRYPT_WORDS(8) * 4

    /// Derives `keyLength` bytes from `password`/`salt`, matching OpenBSD's
    /// `bcrypt_pbkdf(3)` exactly. `rounds` is the outer PBKDF2-style
    /// iteration count (NOT the internal bcrypt cost factor, which this
    /// function fixes at 64 internally, same as the reference).
    static func derive(password: [UInt8], salt: [UInt8], keyLength: Int, rounds: Int) throws -> [UInt8] {
        guard rounds >= 1, !password.isEmpty, !salt.isEmpty, keyLength > 0,
              keyLength <= hashSize * hashSize
        else {
            throw SwiftmikoError.authenticationFailed("Invalid bcrypt_pbkdf parameters")
        }

        let origKeyLength = keyLength
        var remaining = keyLength
        var key = [UInt8](repeating: 0, count: keyLength)

        let stride = (keyLength + hashSize - 1) / hashSize
        var amt = (keyLength + stride - 1) / stride

        let sha2pass = Array(SHA512.hash(data: password))

        var count: UInt32 = 1
        while remaining > 0 {
            var countsalt = salt
            countsalt.append(UInt8((count >> 24) & 0xff))
            countsalt.append(UInt8((count >> 16) & 0xff))
            countsalt.append(UInt8((count >> 8) & 0xff))
            countsalt.append(UInt8(count & 0xff))

            var sha2salt = Array(SHA512.hash(data: countsalt))
            var tmpout = bcryptHash(sha2pass: sha2pass, sha2salt: sha2salt)
            var out = tmpout

            if rounds > 1 {
                for _ in 1..<rounds {
                    sha2salt = Array(SHA512.hash(data: tmpout))
                    tmpout = bcryptHash(sha2pass: sha2pass, sha2salt: sha2salt)
                    for j in 0..<hashSize { out[j] ^= tmpout[j] }
                }
            }

            amt = min(amt, remaining)
            var i = 0
            while i < amt {
                let dest = i * stride + Int(count - 1)
                if dest >= origKeyLength { break }
                key[dest] = out[i]
                i += 1
            }
            remaining -= i
            count += 1
        }

        return key
    }

    /// OpenBSD's internal `bcrypt_hash`: a fixed 64-round EksBlowfish
    /// setup keyed by the SHA-512-hashed password/salt, then 64 rounds
    /// of encrypting a fixed magic string under that schedule.
    private static func bcryptHash(sha2pass: [UInt8], sha2salt: [UInt8]) -> [UInt8] {
        var state = BlowfishState()
        state.expandstate(data: sha2salt, key: sha2pass)
        for _ in 0..<64 {
            state.expand0state(key: sha2salt)
            state.expand0state(key: sha2pass)
        }

        var j = 0
        var cdata = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            cdata[i] = BlowfishState.stream2word(magicCiphertext, &j)
        }

        for _ in 0..<64 {
            var idx = 0
            while idx < 8 {
                var l = cdata[idx]
                var r = cdata[idx + 1]
                state.encipher(&l, &r)
                cdata[idx] = l
                cdata[idx + 1] = r
                idx += 2
            }
        }

        var out = [UInt8](repeating: 0, count: hashSize)
        for i in 0..<8 {
            out[4 * i + 3] = UInt8((cdata[i] >> 24) & 0xff)
            out[4 * i + 2] = UInt8((cdata[i] >> 16) & 0xff)
            out[4 * i + 1] = UInt8((cdata[i] >> 8) & 0xff)
            out[4 * i + 0] = UInt8(cdata[i] & 0xff)
        }
        return out
    }
}
