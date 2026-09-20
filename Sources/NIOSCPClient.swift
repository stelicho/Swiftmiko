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
//  NIOSCPClient.swift
//  Swiftmiko
//
//  SCPClient implementation backed by SwiftNIO SSH.
//
//  Each put/get call opens a fresh SSH connection, starts an exec
//  channel running "scp -t <dest>" or "scp -f <src>", and drives the
//  SCP wire protocol. The connection is closed when the transfer ends.
//

import Foundation
import NIOSSH
import NIOCore
import NIOPosix

// MARK: - Data bridge (NIO push → async pull)

/// Thread-safe buffer that bridges NIO's push-based channelRead into
/// async code that needs to pull exact byte counts or newline-delimited
/// control lines.
private final class SCPDataBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var waiter: CheckedContinuation<Data, Error>?
    private var isClosed = false
    private var closeError: Error?

    func receive(_ bytes: [UInt8]) {
        lock.withLock {
            if let w = waiter {
                waiter = nil
                w.resume(returning: Data(bytes))
            } else {
                pending.append(contentsOf: bytes)
            }
        }
    }

    func closed(error: Error?) {
        lock.withLock {
            isClosed = true
            closeError = error
            if let w = waiter {
                waiter = nil
                if let e = error { w.resume(throwing: e) }
                else             { w.resume(returning: Data()) }
            }
        }
    }

    private func nextChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            lock.withLock {
                if !pending.isEmpty {
                    let d = pending; pending = Data()
                    cont.resume(returning: d)
                } else if isClosed {
                    if let e = closeError { cont.resume(throwing: e) }
                    else                  { cont.resume(returning: Data()) }
                } else {
                    waiter = cont
                }
            }
        }
    }

    /// Read exactly `count` bytes, blocking until they arrive.
    func readExactly(_ count: Int) async throws -> Data {
        var acc = Data()
        while acc.count < count {
            let chunk = try await nextChunk()
            guard !chunk.isEmpty else {
                throw SwiftmikoError.connectionFailed("SCP channel closed prematurely")
            }
            acc.append(chunk)
        }
        if acc.count > count {
            let surplus = Data(acc[count...])
            lock.withLock { pending.insert(contentsOf: surplus, at: 0) }
            return Data(acc.prefix(count))
        }
        return acc
    }

    /// Read bytes up to (not including) the next `\n`.
    func readUntilNewline() async throws -> Data {
        var acc = Data()
        while true {
            let chunk = try await nextChunk()
            guard !chunk.isEmpty else {
                throw SwiftmikoError.connectionFailed("SCP channel closed without newline")
            }
            if let nl = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                acc.append(contentsOf: chunk.prefix(nl))
                let after = Data(chunk[(nl + 1)...])
                if !after.isEmpty { lock.withLock { pending.insert(contentsOf: after, at: 0) } }
                return acc
            }
            acc.append(chunk)
        }
    }
}

// MARK: - NIO channel handlers

private final class SCPChannelDataHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn  = SSHChannelData
    typealias InboundOut = Never

    private let bridge: SCPDataBridge
    init(bridge: SCPDataBridge) { self.bridge = bridge }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var buf) = channelData.data,
              let bytes = buf.readBytes(length: buf.readableBytes) else { return }
        bridge.receive(bytes)
    }

    func channelInactive(context: ChannelHandlerContext) { bridge.closed(error: nil) }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        bridge.closed(error: error)
        context.close(promise: nil)
    }
}

/// Fires an SSH ExecRequest when the channel becomes active, waits
/// for the server's ChannelSuccess reply, then removes itself.
private final class ExecActivationHandler: ChannelInboundHandler, RemovableChannelHandler,
                                           @unchecked Sendable {
    typealias InboundIn  = SSHChannelData
    typealias InboundOut = SSHChannelData

    private let command: String
    private let promise: EventLoopPromise<Void>

    init(command: String, promise: EventLoopPromise<Void>) {
        self.command = command
        self.promise = promise
    }

    func channelActive(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true),
            promise: nil
        )
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is ChannelSuccessEvent {
            promise.succeed(())
            context.pipeline.removeHandler(self, promise: nil)
        } else if event is ChannelFailureEvent {
            promise.fail(
                SwiftmikoError.connectionFailed("SSH exec request rejected: \(command)")
            )
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }
}

// MARK: - NIOSCPClient

/// SCPClient backed by SwiftNIO SSH.
///
/// Opens a dedicated SSH connection per transfer operation and drives
/// the standard SCP sink/source wire protocol over an SSH exec channel.
/// Callers inject this into SCPConn or pass it to fileTransfer():
///
/// ```swift
/// let result = try await fileTransfer(
///     sshConnection: connection,
///     sourceFile: "/tmp/ios.bin",
///     destinationFile: "ios.bin",
///     scpClient: NIOSCPClient(profile: connection.profile)
/// )
/// ```
public final class NIOSCPClient: SCPClient, @unchecked Sendable {
    private let profile: ConnectionProfile

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    // MARK: SCPClient

    public func put(sourceFile: String, destination: String) async throws {
        let fileURL = URL(fileURLWithPath: sourceFile)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SwiftmikoError.connectionFailed("Cannot read \(sourceFile): \(error)")
        }
        let fileName = fileURL.lastPathComponent

        let parent = try await connectSSH()
        do {
            let bridge = SCPDataBridge()
            let exec = try await openExecChannel(
                parent: parent,
                command: "scp -t \(destination)",
                bridge: bridge
            )
            defer { Task { _ = try? await exec.close().get() } }

            try checkACK(try await bridge.readExactly(1), step: "server-ready")
            try await scpWrite(exec, "C0644 \(data.count) \(fileName)\n")
            try checkACK(try await bridge.readExactly(1), step: "header-accepted")
            try await scpWriteData(exec, data)
            try await scpWrite(exec, "\0")
            try checkACK(try await bridge.readExactly(1), step: "transfer-complete")
            _ = try? await parent.close().get()
        } catch {
            _ = try? await parent.close().get()
            throw error
        }
    }

    public func get(sourceFile: String, destination: String) async throws {
        let parent = try await connectSSH()
        do {
            let bridge = SCPDataBridge()
            let exec = try await openExecChannel(
                parent: parent,
                command: "scp -f \(sourceFile)",
                bridge: bridge
            )
            defer { Task { _ = try? await exec.close().get() } }

            // Signal ready, receive control line "C<mode> <size> <name>\n"
            try await scpWrite(exec, "\0")
            let ctrl = try await bridge.readUntilNewline()
            guard let line = String(data: ctrl, encoding: .utf8), line.hasPrefix("C") else {
                throw SwiftmikoError.connectionFailed("Unexpected SCP control response")
            }
            let parts = line.dropFirst().split(separator: " ", maxSplits: 2)
            guard parts.count == 3, let fileSize = Int(parts[1]) else {
                throw SwiftmikoError.connectionFailed("Malformed SCP control line: \(line)")
            }
            try await scpWrite(exec, "\0")
            let fileData = try await bridge.readExactly(fileSize)
            try await scpWrite(exec, "\0")
            _ = try? await bridge.readExactly(1)  // final ACK (best effort)

            do {
                try fileData.write(to: URL(fileURLWithPath: destination))
            } catch {
                throw SwiftmikoError.connectionFailed("Cannot write \(destination): \(error)")
            }
            _ = try? await parent.close().get()
        } catch {
            _ = try? await parent.close().get()
            throw error
        }
    }

    public func close() async {}

    // MARK: Private helpers

    private func connectSSH() async throws -> NIOCore.Channel {
        let authDelegate: any NIOSSHClientUserAuthenticationDelegate & Sendable
        switch profile.auth {
        case .password(let pw):
            authDelegate = PasswordAuthDelegate(username: profile.username, password: pw)
        case .keyFile(let path, let passphrase):
            let nioKey = try SSHKeyLoader.load(path: path, passphrase: passphrase)
            authDelegate = KeyAuthDelegate(username: profile.username, nioKey: nioKey)
        default:
            authDelegate = NoAuthDelegate()
        }

        let bootstrap = ClientBootstrap(group: _swiftmikoNIOGroup)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSHHandler(
                            role: .client(SSHClientConfiguration(
                                userAuthDelegate: authDelegate,
                                serverAuthDelegate: AcceptAllHostKeysDelegate()
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                    )
                }
            }
            .connectTimeout(.seconds(Int64(profile.connectionTimeout)))

        do {
            return try await bootstrap.connect(host: profile.host, port: profile.port).get()
        } catch {
            throw SwiftmikoError.connectionFailed(
                "SCP SSH connect to \(profile.host):\(profile.port) failed: \(error)"
            )
        }
    }

    private func openExecChannel(
        parent: NIOCore.Channel,
        command: String,
        bridge: SCPDataBridge
    ) async throws -> NIOCore.Channel {
        let activationPromise = parent.eventLoop.makePromise(of: Void.self)
        return try await parent.pipeline
            .handler(type: NIOSSHHandler.self)
            .flatMap { ssh -> EventLoopFuture<NIOCore.Channel> in
                let childPromise = parent.eventLoop.makePromise(of: NIOCore.Channel.self)
                ssh.createChannel(childPromise, channelType: .session) { child, type in
                    guard type == .session else {
                        return child.eventLoop.makeFailedFuture(
                            SwiftmikoError.connectionFailed("Expected SSH session channel")
                        )
                    }
                    return child.eventLoop.makeCompletedFuture {
                        let sync = child.pipeline.syncOperations
                        try sync.addHandler(
                            ExecActivationHandler(command: command, promise: activationPromise)
                        )
                        try sync.addHandler(SCPChannelDataHandler(bridge: bridge))
                    }
                }
                return childPromise.futureResult
            }
            .flatMap { ch -> EventLoopFuture<NIOCore.Channel> in
                activationPromise.futureResult.map { ch }
            }
            .get()
    }

    private func scpWrite(_ channel: NIOCore.Channel, _ string: String) async throws {
        var buf = channel.allocator.buffer(capacity: string.utf8.count)
        buf.writeString(string)
        try await channel.writeAndFlush(
            SSHChannelData(type: .channel, data: .byteBuffer(buf))
        ).get()
    }

    private func scpWriteData(_ channel: NIOCore.Channel, _ data: Data) async throws {
        var buf = channel.allocator.buffer(capacity: data.count)
        buf.writeBytes(data)
        try await channel.writeAndFlush(
            SSHChannelData(type: .channel, data: .byteBuffer(buf))
        ).get()
    }

    private func checkACK(_ data: Data, step: String) throws {
        guard let b = data.first else {
            throw SwiftmikoError.connectionFailed("SCP: empty ACK at step '\(step)'")
        }
        guard b == 0x00 else {
            throw SwiftmikoError.connectionFailed(
                "SCP: NACK 0x\(String(b, radix: 16)) at step '\(step)'"
            )
        }
    }
}
