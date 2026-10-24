// Tests/SwiftmikoTests/BCryptPBKDFTests.swift
//
// Test vectors generated via the real Python `bcrypt` package's
// bcrypt.kdf(...) — itself a wrapper around the same reference OpenBSD
// bcrypt_pbkdf implementation this is ported from — not hand-derived.
import XCTest
@testable import Swiftmiko

final class BCryptPBKDFTests: XCTestCase {
    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func testVector0() throws {
        let derived = try BCryptPBKDF.derive(
            password: Array("testpassphrase".utf8),
            salt: Array("0123456789abcdef".utf8),
            keyLength: 48, rounds: 16
        )
        XCTAssertEqual(
            hex(derived),
            "ee7ccaf87899ad12ccefa64e2d81aa40a72c90b88082064fc02d0ce6e2579d81e10c8e4c4ac418f5c3ecdcdf44b8feb0"
        )
    }

    func testVector1() throws {
        let derived = try BCryptPBKDF.derive(
            password: Array("hunter2".utf8),
            salt: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10],
            keyLength: 32, rounds: 4
        )
        XCTAssertEqual(hex(derived), "c6ce31c395788920ce9031d0096de2dfe41f9aadd21fcceba564509c6869046f")
    }

    func testVector2SingleRound() throws {
        let derived = try BCryptPBKDF.derive(
            password: Array("x".utf8),
            salt: Array("saltsaltsaltsalt".utf8),
            keyLength: 32, rounds: 1
        )
        XCTAssertEqual(hex(derived), "8becb660a0bf15b911a8d7538b3af6d49b9bb1117e0af5adf7a3c1dd5ae9df80")
    }

    func testVector3HighRoundCount() throws {
        let derived = try BCryptPBKDF.derive(
            password: Array("correct horse battery staple".utf8),
            salt: [UInt8](repeating: 0xff, count: 16),
            keyLength: 48, rounds: 32
        )
        XCTAssertEqual(
            hex(derived),
            "fa47bc00c93a6f9151000ec6fdd26327f539b1c5eef7acc3ec4e22d3754604acadcaa8fc220e1c8426294e50047c6985"
        )
    }

    func testVector4KeyLengthNotAMultipleOf32() throws {
        let derived = try BCryptPBKDF.derive(
            password: Array("swiftmiko-test".utf8),
            salt: [0xaa, 0xbb, 0xcc, 0xdd, 0xaa, 0xbb, 0xcc, 0xdd, 0xaa, 0xbb, 0xcc, 0xdd, 0xaa, 0xbb, 0xcc, 0xdd],
            keyLength: 20, rounds: 8
        )
        XCTAssertEqual(hex(derived), "100b68dc2fa62277c8845d9f04080a64bb52f510")
    }

    func testVector5LargerThan64Bytes() throws {
        let derived = try BCryptPBKDF.derive(
            password: Array("another passphrase here".utf8),
            salt: Array("0123456789ABCDEF".utf8),
            keyLength: 64, rounds: 16
        )
        XCTAssertEqual(
            hex(derived),
            "c7d6b22b39831fb40a2e20d4fda94c6bf034c68a77b8a3e5f459a41517a297af0dc11f04b4902226fe07bdb8bfc86ebd2fe7a7db9614c9d1c000a24018fa7a45"
        )
    }

    func testInvalidParametersThrow() {
        XCTAssertThrowsError(try BCryptPBKDF.derive(password: [], salt: [1], keyLength: 32, rounds: 1))
        XCTAssertThrowsError(try BCryptPBKDF.derive(password: [1], salt: [], keyLength: 32, rounds: 1))
        XCTAssertThrowsError(try BCryptPBKDF.derive(password: [1], salt: [1], keyLength: 0, rounds: 1))
        XCTAssertThrowsError(try BCryptPBKDF.derive(password: [1], salt: [1], keyLength: 32, rounds: 0))
    }
}
