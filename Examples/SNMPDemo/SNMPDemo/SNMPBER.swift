// Examples/SNMPDemo/SNMPBER.swift
//
// A minimal BER (Basic Encoding Rules, ITU-T X.690) encoder/decoder for
// SNMP v1/v2c GET-request messages only — just enough to satisfy
// Swiftmiko's `SNMPTransport` injection point for this demo. It does
// not attempt to be a general-purpose ASN.1 library: no SET-request,
// no bulk-walk, no v3/USM authentication or privacy.

import Foundation

enum SNMPBERError: Error, LocalizedError {
    case truncatedMessage
    case unexpectedTag(expected: UInt8, found: UInt8)
    case invalidOID(String)
    case requestIDMismatch
    case errorStatus(Int)

    var errorDescription: String? {
        switch self {
        case .truncatedMessage:
            return "The SNMP response was truncated or malformed."
        case .unexpectedTag(let expected, let found):
            return String(
                format: "Unexpected SNMP BER tag: expected 0x%02X, found 0x%02X.",
                expected, found
            )
        case .invalidOID(let oid):
            return "Invalid OID: \(oid)"
        case .requestIDMismatch:
            return "The SNMP response's request-id didn't match the request."
        case .errorStatus(let status):
            return "The SNMP agent returned error-status \(status)."
        }
    }
}

/// A single decoded Tag-Length-Value from a BER stream.
struct SNMPTLV {
    let tag: UInt8
    let value: ArraySlice<UInt8>
}

enum SNMPBEREncoder {
    static func encodeLength(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [UInt8(0x80 | bytes.count)] + bytes
    }

    static func encodeTLV(tag: UInt8, value: [UInt8]) -> [UInt8] {
        [tag] + encodeLength(value.count) + value
    }

    /// Demo scope only handles the small, non-negative integers SNMP
    /// GET requests actually need (version, request-id, error-status,
    /// error-index) — not arbitrary signed/wide integers.
    static func encodeInteger(_ value: Int) -> [UInt8] {
        precondition(value >= 0, "this demo encoder only handles non-negative integers")
        var magnitude = UInt64(value)
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(magnitude & 0xFF), at: 0)
            magnitude >>= 8
        } while magnitude > 0
        // BER INTEGER is signed — prepend a 0x00 if the high bit of the
        // first byte is already set, so it isn't misread as negative.
        if bytes[0] & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return encodeTLV(tag: 0x02, value: bytes)
    }

    static func encodeOctetString(_ string: String) -> [UInt8] {
        encodeTLV(tag: 0x04, value: Array(string.utf8))
    }

    static func encodeNull() -> [UInt8] {
        [0x05, 0x00]
    }

    private static func encodeBase128(_ value: Int) -> [UInt8] {
        if value == 0 { return [0x00] }
        var v = value
        var septets: [UInt8] = []
        while v > 0 {
            septets.insert(UInt8(v & 0x7F), at: 0)
            v >>= 7
        }
        for i in 0..<(septets.count - 1) {
            septets[i] |= 0x80
        }
        return septets
    }

    /// `oid` is a dotted string like ".1.3.6.1.2.1.1.1.0" (leading dot
    /// is tolerated and ignored, matching how SNMPAutodetectMapper's
    /// rules are written).
    static func encodeOID(_ oid: String) throws -> [UInt8] {
        let components = oid.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else {
            throw SNMPBERError.invalidOID(oid)
        }
        var body = encodeBase128(components[0] * 40 + components[1])
        for component in components.dropFirst(2) {
            body.append(contentsOf: encodeBase128(component))
        }
        return encodeTLV(tag: 0x06, value: body)
    }

    static func encodeSequence(_ elements: [[UInt8]]) -> [UInt8] {
        encodeTLV(tag: 0x30, value: elements.flatMap { $0 })
    }

    /// Builds a complete SNMP v1/v2c GetRequest message for a single OID.
    static func encodeGetRequest(
        version: Int,
        community: String,
        requestID: Int32,
        oid: String
    ) throws -> Data {
        let varBind = encodeSequence([try encodeOID(oid), encodeNull()])
        let varBindList = encodeSequence([varBind])

        let pduBody = encodeInteger(Int(requestID)) +
            encodeInteger(0) + // error-status
            encodeInteger(0) + // error-index
            varBindList

        // GetRequest-PDU is context tag [0], constructed.
        let pdu = encodeTLV(tag: 0xA0, value: pduBody)

        let message = encodeSequence([
            encodeInteger(version),
            encodeOctetString(community),
            pdu
        ])

        return Data(message)
    }
}

enum SNMPBERDecoder {
    static func readTLV(_ bytes: ArraySlice<UInt8>) throws -> (SNMPTLV, ArraySlice<UInt8>) {
        var remaining = bytes
        guard let tag = remaining.popFirst() else { throw SNMPBERError.truncatedMessage }
        guard let firstLengthByte = remaining.popFirst() else { throw SNMPBERError.truncatedMessage }

        let length: Int
        if firstLengthByte & 0x80 == 0 {
            length = Int(firstLengthByte)
        } else {
            let numBytes = Int(firstLengthByte & 0x7F)
            guard remaining.count >= numBytes else { throw SNMPBERError.truncatedMessage }
            var len = 0
            for _ in 0..<numBytes {
                len = (len << 8) | Int(remaining.popFirst()!)
            }
            length = len
        }

        guard remaining.count >= length else { throw SNMPBERError.truncatedMessage }
        let value = remaining.prefix(length)
        let rest = remaining.dropFirst(length)
        return (SNMPTLV(tag: tag, value: value), rest)
    }

    static func decodeInteger(_ value: ArraySlice<UInt8>) -> Int {
        guard let first = value.first else { return 0 }
        let negative = (first & 0x80) != 0
        var result = 0
        for byte in value {
            result = (result << 8) | Int(byte)
        }
        if negative {
            result -= (1 << (value.count * 8))
        }
        return result
    }

    static func decodeUnsignedInteger(_ value: ArraySlice<UInt8>) -> UInt64 {
        var result: UInt64 = 0
        for byte in value {
            result = (result << 8) | UInt64(byte)
        }
        return result
    }

    static func decodeOID(_ value: ArraySlice<UInt8>) -> String {
        var bytes = Array(value)
        guard let first = bytes.first else { return "" }
        var components = [Int(first) / 40, Int(first) % 40]
        bytes.removeFirst()
        var current = 0
        for byte in bytes {
            current = (current << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                components.append(current)
                current = 0
            }
        }
        return components.map(String.init).joined(separator: ".")
    }

    /// Returns the string representation of the first varbind's value in
    /// an SNMP GetResponse message, or `nil` for NULL / noSuchObject /
    /// noSuchInstance / endOfMibView values.
    static func decodeVarBindValue(from data: Data, expectedRequestID: Int32) throws -> String? {
        let (messageTLV, _) = try readTLV(ArraySlice(data))
        guard messageTLV.tag == 0x30 else {
            throw SNMPBERError.unexpectedTag(expected: 0x30, found: messageTLV.tag)
        }

        var fields = messageTLV.value
        (_, fields) = try readTLV(fields) // version — not needed by this demo
        (_, fields) = try readTLV(fields) // community — not needed by this demo

        let (pduTLV, _) = try readTLV(fields)
        // GetResponse-PDU is context tag [2], constructed.
        guard pduTLV.tag == 0xA2 else {
            throw SNMPBERError.unexpectedTag(expected: 0xA2, found: pduTLV.tag)
        }

        var pduFields = pduTLV.value
        let requestIDTLV: SNMPTLV
        (requestIDTLV, pduFields) = try readTLV(pduFields)
        let errorStatusTLV: SNMPTLV
        (errorStatusTLV, pduFields) = try readTLV(pduFields)
        (_, pduFields) = try readTLV(pduFields) // error-index — not needed by this demo

        guard Int32(truncatingIfNeeded: decodeInteger(requestIDTLV.value)) == expectedRequestID else {
            throw SNMPBERError.requestIDMismatch
        }

        let errorStatus = decodeInteger(errorStatusTLV.value)
        guard errorStatus == 0 else {
            throw SNMPBERError.errorStatus(errorStatus)
        }

        let (varBindListTLV, _) = try readTLV(pduFields)
        guard varBindListTLV.tag == 0x30 else {
            throw SNMPBERError.unexpectedTag(expected: 0x30, found: varBindListTLV.tag)
        }

        let (firstVarBindTLV, _) = try readTLV(varBindListTLV.value)
        guard firstVarBindTLV.tag == 0x30 else {
            throw SNMPBERError.unexpectedTag(expected: 0x30, found: firstVarBindTLV.tag)
        }

        var varBindFields = firstVarBindTLV.value
        (_, varBindFields) = try readTLV(varBindFields) // OID name — not needed by this demo
        let (valueTLV, _) = try readTLV(varBindFields)

        return stringify(valueTLV)
    }

    private static func stringify(_ tlv: SNMPTLV) -> String? {
        switch tlv.tag {
        case 0x04: // OCTET STRING
            return String(decoding: tlv.value, as: UTF8.self)
        case 0x02: // INTEGER
            return String(decodeInteger(tlv.value))
        case 0x06: // OBJECT IDENTIFIER
            return decodeOID(tlv.value)
        case 0x40: // IpAddress
            return tlv.value.map(String.init).joined(separator: ".")
        case 0x41, 0x42, 0x43, 0x46: // Counter32, Gauge32/Unsigned32, TimeTicks, Counter64
            return String(decodeUnsignedInteger(tlv.value))
        default: // NULL, noSuchObject (0x80), noSuchInstance (0x81), endOfMibView (0x82), anything else
            return nil
        }
    }
}
