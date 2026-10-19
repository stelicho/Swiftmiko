// Tests/SwiftmikoTests/NIOSCPClientTests.swift
//
// Direct behavioral coverage for a bug found in a fresh adversarial
// pass over NIOSCPClient — hand-rolled SCP wire-protocol code with no
// upstream Netmiko source to translate from (Netmiko delegates to the
// `scp` Python package).
//
// Standard scp protocol for a single file transfer is:
//   source -> sink: "C<mode> <size> <name>\n"
//   sink -> source: ack byte (0x00)
//   source -> sink: <size> raw bytes of file data
//   source -> sink: one trailing status byte (0x00 = ok)
//   sink -> source: ack byte (0x00)
//
// get() plays the SINK role. Before the fix, it wrote its own ack
// BEFORE reading the source's trailing status byte, and that status
// byte was read as "best effort" and discarded — so a non-zero status
// from the source (signaling a transfer problem after it had already
// announced the file size) was silently ignored, and a truncated or
// corrupted transfer would be reported as a success.
//
// receiveFile() was pulled out of get() as a pure, dependency-injected
// function specifically so this sequencing and error-handling could be
// tested without a live SSH connection.

import XCTest
@testable import Swiftmiko

final class NIOSCPClientTests: XCTestCase {
    /// A minimal in-memory stand-in for the source side of the scp
    /// protocol, scripted with the exact sequence of bytes a real
    /// remote `scp -f` process would send.
    private final class ScriptedSource {
        private(set) var writes: [String] = []
        private var fileSize: Int
        private var fileName: String
        private var fileBytes: Data
        private var trailingStatusByte: UInt8
        /// Explicit phase tracking (rather than inferring from byte
        /// counts) so this mock stays correct regardless of file size.
        private var hasServedFileData = false

        init(fileName: String, fileBytes: Data, trailingStatusByte: UInt8 = 0x00) {
            self.fileName = fileName
            self.fileBytes = fileBytes
            self.fileSize = fileBytes.count
            self.trailingStatusByte = trailingStatusByte
        }

        func write(_ string: String) async throws {
            writes.append(string)
        }

        func readUntilNewline() async throws -> Data {
            Data("C0644 \(fileSize) \(fileName)".utf8)
        }

        /// Returns exactly `count` bytes, serving the file's raw bytes
        /// first and the trailing status byte once the file has been
        /// fully consumed — mirroring the real wire order.
        func readExactly(_ count: Int) async throws -> Data {
            guard hasServedFileData else {
                hasServedFileData = true
                return fileBytes
            }
            precondition(count == 1, "only the trailing status byte should be read after the file data")
            return Data([trailingStatusByte])
        }
    }

    func testReceiveFileValidatesTheSourcesTrailingStatusByteAndSendsItsOwnAckOnlyAfter() async throws {
        let source = ScriptedSource(fileName: "ios.bin", fileBytes: Data("hello world".utf8))

        let data = try await NIOSCPClient.receiveFile(
            write: { try await source.write($0) },
            readUntilNewline: { try await source.readUntilNewline() },
            readExactly: { try await source.readExactly($0) }
        )

        XCTAssertEqual(data, Data("hello world".utf8))
        // Three writes expected: the initial "ready" signal, the
        // header ack, and the final ack — sent only AFTER the status
        // byte was read and validated.
        XCTAssertEqual(source.writes, ["\0", "\0", "\0"])
    }

    func testReceiveFileThrowsWhenTheSourceSignalsAFailureAfterSendingTheData() async throws {
        // Before the fix, this non-zero trailing status byte was
        // discarded via `try?` and the transfer was reported as
        // successful even though the source flagged a problem.
        let source = ScriptedSource(
            fileName: "ios.bin",
            fileBytes: Data("truncated data".utf8),
            trailingStatusByte: 0x01
        )

        do {
            _ = try await NIOSCPClient.receiveFile(
                write: { try await source.write($0) },
                readUntilNewline: { try await source.readUntilNewline() },
                readExactly: { try await source.readExactly($0) }
            )
            XCTFail("Expected receiveFile() to throw on a non-zero trailing status byte")
        } catch {
            // Expected.
        }

        // The final ack must NOT have been sent — we found out the
        // transfer was bad before ever getting to that point.
        XCTAssertEqual(source.writes, ["\0", "\0"])
    }

    func testReceiveFileThrowsOnAMalformedControlLine() async throws {
        do {
            _ = try await NIOSCPClient.receiveFile(
                write: { _ in },
                readUntilNewline: { Data("not-a-control-line".utf8) },
                readExactly: { _ in Data() }
            )
            XCTFail("Expected receiveFile() to throw on a malformed control line")
        } catch {
            // Expected.
        }
    }
}
