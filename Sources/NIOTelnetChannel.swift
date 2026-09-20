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
//  NIOTelnetChannel.swift
//  Swiftmiko
//
//  Concrete Channel implementation for Telnet, backed by a plain NIO TCP
//  connection with in-pipeline IAC option negotiation.
//
//  Conforms to both Channel (used by BaseConnection) AND
//  TelnetNegotiatingChannel (used by drivers that require direct IAC
//  control: ZteZxrosTelnet, IpInfusionOcNOSTelnet, NecIxTelnet, etc.).
//
//  IAC handling:
//  - By default the handler auto-negotiates: agrees to ECHO/SGA (suppress
//    go-ahead) when the server offers them, refuses everything else.
//  - Drivers that need custom negotiation install a callback via
//    setOptionNegotiationCallback(_:), which fully replaces the default.
//  - Subnegotiation blocks (IAC SB … IAC SE) are parsed and stripped from
//    the data stream; the raw bytes are not surfaced to the read buffer.
//

import Foundation
import NIOCore
import NIOPosix

// MARK: - IAC stream parser / negotiation handler

private final class TelnetIACHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn  = ByteBuffer
    typealias InboundOut = ByteBuffer

    private enum ParseState {
        case normal
        case sawIAC
        case sawCmd(UInt8)
        case inSB
        case sawIACInSB
    }

    private var state: ParseState = .normal
    private var sbPayload: [UInt8] = []

    private let lock = NSLock()
    private var optionCallback: (@Sendable (UInt8, UInt8) async throws -> Void)?

    func setCallback(
        _ cb: @escaping @Sendable (UInt8, UInt8) async throws -> Void
    ) {
        lock.lock(); defer { lock.unlock() }
        optionCallback = cb
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        var clean = [UInt8]()
        clean.reserveCapacity(buf.readableBytes)

        while buf.readableBytes > 0 {
            guard let byte = buf.readInteger(as: UInt8.self) else { break }

            switch state {
            case .normal:
                if byte == TelnetOption.IAC { state = .sawIAC }
                else { clean.append(byte) }

            case .sawIAC:
                switch byte {
                case TelnetOption.IAC:
                    clean.append(TelnetOption.IAC)   // escaped 0xFF in data
                    state = .normal
                case TelnetOption.WILL, TelnetOption.WONT,
                     TelnetOption.DO,   TelnetOption.DONT:
                    state = .sawCmd(byte)
                case TelnetOption.SB:
                    sbPayload = []
                    state = .inSB
                default:
                    state = .normal                  // 2-byte cmd (NOP, GA, …)
                }

            case .sawCmd(let cmd):
                state = .normal
                negotiate(context: context, command: cmd, option: byte)

            case .inSB:
                if byte == TelnetOption.IAC { state = .sawIACInSB }
                else { sbPayload.append(byte) }

            case .sawIACInSB:
                if byte == TelnetOption.SE {
                    sbPayload = []
                    state = .normal
                } else {
                    // Escaped IAC inside SB payload
                    sbPayload.append(byte)
                    state = .inSB
                }
            }
        }

        if !clean.isEmpty {
            var out = context.channel.allocator.buffer(capacity: clean.count)
            out.writeBytes(clean)
            context.fireChannelRead(wrapInboundOut(out))
        }
    }

    private func negotiate(
        context: ChannelHandlerContext,
        command: UInt8,
        option: UInt8
    ) {
        lock.lock()
        let cb = optionCallback
        lock.unlock()

        if let cb {
            Task { try? await cb(command, option) }
            return
        }

        // Default: agree to ECHO and SGA; refuse everything else.
        let response: (cmd: UInt8, opt: UInt8)?
        switch command {
        case TelnetOption.WILL:
            let accept = option == TelnetOption.ECHO || option == TelnetOption.SGA
            response = (accept ? TelnetOption.DO : TelnetOption.DONT, option)
        case TelnetOption.DO:
            let accept = option == TelnetOption.SGA
            response = (accept ? TelnetOption.WILL : TelnetOption.WONT, option)
        case TelnetOption.WONT:
            response = (TelnetOption.DONT, option)
        case TelnetOption.DONT:
            response = (TelnetOption.WONT, option)
        default:
            response = nil
        }

        if let r = response {
            var out = context.channel.allocator.buffer(capacity: 3)
            out.writeBytes([TelnetOption.IAC, r.cmd, r.opt])
            context.writeAndFlush(NIOAny(out), promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - Clean-text read buffer

private final class TelnetReadBufferHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn  = ByteBuffer
    typealias InboundOut = ByteBuffer

    private let lock = NSLock()
    private var buffer = ""

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        guard let chunk = buf.readString(length: buf.readableBytes), !chunk.isEmpty else { return }
        lock.lock(); buffer += chunk; lock.unlock()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    func drain() -> String {
        lock.lock(); defer { lock.unlock() }
        let s = buffer; buffer = ""; return s
    }
}

// MARK: - NIOTelnetChannel

/// Real Telnet transport conforming to Channel and TelnetNegotiatingChannel.
///
/// Usage via ChannelProvider (wired automatically by SSHDispatcher for
/// `_telnet` device types):
/// ```swift
/// let provider: ChannelProvider = { profile in NIOTelnetChannel(profile: profile) }
/// ```
///
/// Note: Telnet's default port is 23. Set `port: 23` in `ConnectionProfile`
/// when connecting to a standard Telnet endpoint; the dispatcher does NOT
/// override the port from the profile.
public final class NIOTelnetChannel: Swiftmiko.Channel, TelnetNegotiatingChannel,
                                     @unchecked Sendable {

    private let profile: ConnectionProfile
    private let iacHandler  = TelnetIACHandler()
    private let readHandler = TelnetReadBufferHandler()
    private var nioChannel: NIOCore.Channel?

    public private(set) var isOpen = false

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    // MARK: Channel — lifecycle

    public func open() async throws {
        let iac  = iacHandler
        let read = readHandler

        let bootstrap = ClientBootstrap(group: _swiftmikoNIOGroup)
            .channelInitializer { ch in
                ch.pipeline.addHandlers([iac, read])
            }
            .connectTimeout(.seconds(Int64(profile.connectionTimeout)))
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)

        do {
            let ch = try await bootstrap
                .connect(host: profile.host, port: profile.port)
                .get()
            nioChannel = ch
            isOpen = true
        } catch {
            throw SwiftmikoError.connectionFailed(
                "Telnet connect to \(profile.host):\(profile.port) failed: \(error)"
            )
        }
    }

    /// No-op: Telnet credentials are exchanged via telnetLogin() which
    /// uses the standard writeChannel / readChannel pair.
    public func authenticate(username: String, using method: AuthMethod) async throws {}

    // MARK: Channel — I/O

    public func write(_ data: String) async throws {
        guard isOpen, let ch = nioChannel else { throw SwiftmikoError.channelClosed }
        // Escape any 0xFF bytes so they are not misinterpreted as IAC by the peer.
        var bytes = [UInt8]()
        bytes.reserveCapacity(data.utf8.count)
        for b in data.utf8 {
            if b == TelnetOption.IAC { bytes.append(TelnetOption.IAC) }
            bytes.append(b)
        }
        var buf = ch.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        try await ch.writeAndFlush(buf).get()
    }

    public func readAvailable() async throws -> String {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        return readHandler.drain()
    }

    public func close() async {
        isOpen = false
        if let ch = nioChannel {
            try? await ch.close().get()
        }
        nioChannel = nil
    }

    // MARK: TelnetSocket — raw byte I/O

    public func write(_ data: Data) async throws {
        guard isOpen, let ch = nioChannel else { throw SwiftmikoError.channelClosed }
        var buf = ch.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        try await ch.writeAndFlush(buf).get()
    }

    public func read(maxLength: Int) async throws -> Data {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        let s = readHandler.drain()
        return Data(s.utf8.prefix(maxLength))
    }

    // MARK: TelnetNegotiatingChannel — direct IAC control

    public func sendRawOption(command: UInt8, option: UInt8) async throws {
        guard isOpen, let ch = nioChannel else { throw SwiftmikoError.channelClosed }
        var buf = ch.allocator.buffer(capacity: 3)
        buf.writeBytes([TelnetOption.IAC, command, option])
        try await ch.writeAndFlush(buf).get()
    }

    public func sendSubnegotiation(option: UInt8, payload: [UInt8]) async throws {
        guard isOpen, let ch = nioChannel else { throw SwiftmikoError.channelClosed }
        var bytes = [TelnetOption.IAC, TelnetOption.SB, option]
        bytes += payload
        bytes += [TelnetOption.IAC, TelnetOption.SE]
        var buf = ch.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        try await ch.writeAndFlush(buf).get()
    }

    public func setOptionNegotiationCallback(
        _ callback: @escaping @Sendable (UInt8, UInt8) async throws -> Void
    ) async {
        iacHandler.setCallback(callback)
    }
}

// MARK: - Default Telnet channel provider

public let nioTelnetChannelProvider: ChannelProvider = { profile in
    NIOTelnetChannel(profile: profile)
}
