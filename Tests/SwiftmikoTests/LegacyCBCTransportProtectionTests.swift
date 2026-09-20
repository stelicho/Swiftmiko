// Tests/SwiftmikoTests/LegacyCBCTransportProtectionTests.swift
//
// Diagnostic test written while debugging a real Cisco C7200 connection
// that got an "Unexpected message type has arrived" error from the router
// after cipher/KEX/host-key negotiation all succeeded. Isolates the CBC
// cipher's correctness (chaining, MAC, framing) using fabricated-but-
// mutually-consistent client/server keys, independent of KEX/key
// derivation — no NIOSSHHandler or real key exchange involved.

import Crypto
import NIOCore
import NIOSSH
import XCTest

@testable import Swiftmiko

final class LegacyCBCTransportProtectionTests: XCTestCase {
    /// Matches SSHPacketSerializer.writeSSHPacket's framing for
    /// lengthEncrypted=true (the CBC case): packet_length(4) is part of
    /// what gets padded-for and encrypted, but excludes itself from the
    /// count it stores.
    private func makePlaintextPacket(payload: [UInt8], blockSize: Int = 16) -> ByteBuffer {
        let messageLength = payload.count
        let payloadLengthForPadding = messageLength + 5
        var paddingLength = blockSize - (payloadLengthForPadding % blockSize)
        if paddingLength < 4 {
            paddingLength += blockSize
        }
        let packetLength = 1 + messageLength + paddingLength

        var buffer = ByteBuffer()
        buffer.writeInteger(UInt32(packetLength))
        buffer.writeInteger(UInt8(paddingLength))
        buffer.writeBytes(payload)
        buffer.writeBytes([UInt8](repeating: 0xAA, count: paddingLength))
        return buffer
    }

    func testCBCRoundTripAcrossManyPackets() throws {
        // Fabricated (not KEX-derived) but mutually consistent client/server
        // keys. This isolates the cipher's own correctness from key
        // derivation — the real handshake already proved key derivation is
        // correct (a mismatch there would fail signature verification
        // locally, not produce a router-side protocol error).
        let ivClientToServer: [UInt8] = (0..<16).map { UInt8($0) }
        let ivServerToClient: [UInt8] = (0..<16).map { UInt8(0x10 + $0) }
        let encClientToServer = SymmetricKey(data: (0..<16).map { UInt8(0x20 + $0) })
        let encServerToClient = SymmetricKey(data: (0..<16).map { UInt8(0x30 + $0) })
        let macClientToServer = SymmetricKey(data: (0..<20).map { UInt8(0x40 + $0) })
        let macServerToClient = SymmetricKey(data: (0..<20).map { UInt8(0x50 + $0) })

        let clientKeys = NIOSSHSessionKeys(
            initialInboundIV: ivServerToClient,
            initialOutboundIV: ivClientToServer,
            inboundEncryptionKey: encServerToClient,
            outboundEncryptionKey: encClientToServer,
            inboundMACKey: macServerToClient,
            outboundMACKey: macClientToServer
        )
        let serverKeys = NIOSSHSessionKeys(
            initialInboundIV: ivClientToServer,
            initialOutboundIV: ivServerToClient,
            inboundEncryptionKey: encClientToServer,
            outboundEncryptionKey: encServerToClient,
            inboundMACKey: macClientToServer,
            outboundMACKey: macServerToClient
        )

        let client = try AES128CBCHMACSHA1TransportProtection(initialKeys: clientKeys)
        let server = try AES128CBCHMACSHA1TransportProtection(initialKeys: serverKeys)

        // Many consecutive packets of varying length, to exercise CBC
        // chaining across packet boundaries (a chaining bug often only
        // shows up from the second packet onward).
        for seq in UInt32(0)..<50 {
            let payload = Array("test payload number \(seq) with some extra length to vary the padding".utf8)
            var packet = makePlaintextPacket(payload: payload)

            try client.encryptPacket(&packet, sequenceNumber: seq)

            try server.decryptFirstBlock(&packet)
            let recovered = try server.decryptAndVerifyRemainingPacket(&packet, sequenceNumber: seq)

            XCTAssertEqual(Array(recovered.readableBytesView), payload, "round trip failed at sequence \(seq)")
        }
    }

    func testServerToClientDirectionAlsoRoundTrips() throws {
        // Same as above, but sends packets the other direction, since the
        // cipher/MAC objects for each direction are logically independent
        // CCCryptor chains that could have an asymmetric bug.
        let ivClientToServer: [UInt8] = (0..<16).map { UInt8($0) }
        let ivServerToClient: [UInt8] = (0..<16).map { UInt8(0x60 + $0) }
        let encClientToServer = SymmetricKey(data: (0..<16).map { UInt8(0x70 + $0) })
        let encServerToClient = SymmetricKey(data: (0..<16).map { UInt8(0x80 + $0) })
        let macClientToServer = SymmetricKey(data: (0..<20).map { UInt8(0x90 + $0) })
        let macServerToClient = SymmetricKey(data: (0..<20).map { UInt8(0xA0 + $0) })

        let clientKeys = NIOSSHSessionKeys(
            initialInboundIV: ivServerToClient,
            initialOutboundIV: ivClientToServer,
            inboundEncryptionKey: encServerToClient,
            outboundEncryptionKey: encClientToServer,
            inboundMACKey: macServerToClient,
            outboundMACKey: macClientToServer
        )
        let serverKeys = NIOSSHSessionKeys(
            initialInboundIV: ivClientToServer,
            initialOutboundIV: ivServerToClient,
            inboundEncryptionKey: encClientToServer,
            outboundEncryptionKey: encServerToClient,
            inboundMACKey: macClientToServer,
            outboundMACKey: macServerToClient
        )

        let client = try AES128CBCHMACSHA1TransportProtection(initialKeys: clientKeys)
        let server = try AES128CBCHMACSHA1TransportProtection(initialKeys: serverKeys)

        for seq in UInt32(0)..<50 {
            let payload = Array("server payload \(seq)".utf8)
            var packet = makePlaintextPacket(payload: payload)

            try server.encryptPacket(&packet, sequenceNumber: seq)

            try client.decryptFirstBlock(&packet)
            let recovered = try client.decryptAndVerifyRemainingPacket(&packet, sequenceNumber: seq)

            XCTAssertEqual(Array(recovered.readableBytesView), payload, "round trip failed at sequence \(seq)")
        }
    }
}
