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
//  TelnetProxy.swift
//  Swiftmiko
//
//  Port of netmiko/telnet_proxy.py
//
//  REWORKED: adds TelnetOption + TelnetNegotiatingChannel, which
//  ZteZxrosTelnet, IpInfusionOcNOSTelnet, and NecIxTelnet all assumed
//  existed here but never actually did. Also fixes the silent
//  double-open bug flagged in the original review.
//

import Foundation

public struct SOCKSProxyConfiguration: Sendable {
    public let proxyType: Int
    public let proxyAddress: String
    public let proxyPort: Int
    public let username: String?
    public let password: String?

    public init(
        proxyType: Int,
        proxyAddress: String,
        proxyPort: Int,
        username: String? = nil,
        password: String? = nil
    ) {
        self.proxyType = proxyType
        self.proxyAddress = proxyAddress
        self.proxyPort = proxyPort
        self.username = username
        self.password = password
    }
}

public enum TelnetProxyError: Error {
    case noTransport
    case socksTransportUnavailable
    case invalidHost
    case alreadyConnected
}

// MARK: - Raw IAC Telnet Option Constants

/// Telnet IAC negotiation byte values (RFC 854/855 and friends).
///
/// Confirmed needed, in this exact shape, by ZteZxrosTelnet,
/// IpInfusionOcNOSTelnet, and NecIxTelnet — all three drivers wrote
/// against this without it actually existing.
public enum TelnetOption {
    public static let IAC: UInt8 = 255
    public static let DO: UInt8 = 253
    public static let DONT: UInt8 = 254
    public static let WILL: UInt8 = 251
    public static let WONT: UInt8 = 252
    public static let SB: UInt8 = 250
    public static let SE: UInt8 = 240
    public static let ECHO: UInt8 = 1
    public static let SGA: UInt8 = 3
    public static let NAWS: UInt8 = 31
    /// Terminal type — needed by IpInfusionOcNOSTelnet specifically.
    public static let TTYPE: UInt8 = 24
}

/// A telnet channel capable of raw IAC option negotiation.
///
/// Most devices never need this — negotiation is handled
/// transparently by the transport layer. A small number of devices
/// (ZTE ZXROS, IP Infusion OcNOS, NEC IX) require the client to
/// answer specific negotiation requests by hand.
public protocol TelnetNegotiatingChannel: TelnetSocket {
    /// Reply to a single-option IAC negotiation request,
    /// e.g. IAC DO ECHO.
    func sendRawOption(command: UInt8, option: UInt8) async throws

    /// Send an IAC subnegotiation block, e.g. IAC SB NAWS <payload> IAC SE.
    func sendSubnegotiation(option: UInt8, payload: [UInt8]) async throws

    /// Register a callback invoked for every incoming negotiation
    /// command/option pair the transport observes.
    func setOptionNegotiationCallback(
        _ callback: @escaping @Sendable (UInt8, UInt8) async throws -> Void
    ) async
}

public protocol TelnetSocket: AnyObject {
    func write(_ data: Data) async throws
    func read(maxLength: Int) async throws -> Data
    func close() async
}

public protocol TelnetSocketConnector: AnyObject {
    func connect(
        host: String,
        port: Int,
        timeout: TimeInterval,
        proxy: SOCKSProxyConfiguration?
    ) async throws -> TelnetSocket
}

public final class Telnet {
    public static let telnetPort = 23

    public private(set) var host: String?
    public private(set) var port: Int
    public private(set) var timeout: TimeInterval
    public let proxy: SOCKSProxyConfiguration?

    private let connector: TelnetSocketConnector?
    private var socket: TelnetSocket?

    public init(
        host: String? = nil,
        port: Int = 0,
        timeout: TimeInterval = 60.0,
        proxy: SOCKSProxyConfiguration? = nil,
        connector: TelnetSocketConnector? = nil
    ) async throws {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.proxy = proxy
        self.connector = connector

        if let host {
            try await open(host: host, port: port, timeout: timeout)
        }
    }

    /// Connect to a host. Now THROWS on a redundant open rather than
    /// silently doing nothing — flagged in the original review as a
    /// bug risk: a caller thinking they'd reconnected could otherwise
    /// keep using a stale socket without any signal something was
    /// wrong.
    public func open(
        host: String,
        port: Int = 0,
        timeout: TimeInterval = 60.0
    ) async throws {
        guard !host.isEmpty else { throw TelnetProxyError.invalidHost }
        guard socket == nil else {
            throw TelnetProxyError.alreadyConnected
        }
        guard let connector else {
            if proxy != nil { throw TelnetProxyError.socksTransportUnavailable }
            throw TelnetProxyError.noTransport
        }

        let destinationPort = port == 0 ? Self.telnetPort : port
        self.host = host
        self.port = destinationPort
        self.timeout = timeout
        socket = try await connector.connect(
            host: host, port: destinationPort, timeout: timeout, proxy: proxy
        )
    }

    public func close() async {
        await socket?.close()
        socket = nil
    }

    public func write(_ data: Data) async throws {
        guard let socket else { throw TelnetProxyError.noTransport }
        try await socket.write(data)
    }

    public func read(maxLength: Int = 4_096) async throws -> Data {
        guard let socket else { throw TelnetProxyError.noTransport }
        return try await socket.read(maxLength: maxLength)
    }

    public var isOpen: Bool { socket != nil }
}
