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
//  NIOSSHChannel.swift
//  Swiftmiko
//
//  Concrete Channel implementation backed by SwiftNIO SSH.
//
//  Architecture:
//  - open() performs TCP connect, SSH handshake, authentication (via delegate),
//    and opens an interactive shell channel — all in one step, because NIO SSH
//    interleaves key exchange and user-auth during connection setup and there is
//    no natural pause point between them.
//  - authenticate() is a no-op; credentials are fed to the NIO SSH auth delegate
//    at construction time and exercised automatically during open().
//  - A single module-level MultiThreadedEventLoopGroup is shared across all
//    instances to avoid spawning one thread per connection.
//

import Foundation
import NIOSSH
import NIOCore
import NIOPosix

// MARK: - Shared event loop group

// Shared across all NIOSSHChannel and NIOTelnetChannel instances.
let _swiftmikoNIOGroup = MultiThreadedEventLoopGroup(
    numberOfThreads: max(2, System.coreCount)
)

// MARK: - User-auth delegate: password

// @unchecked Sendable: each instance is single-use per connection attempt,
// mutated only by NIOSSHHandler's serial calls to nextAuthenticationType(:)
// on the channel's event loop — never shared across connections or threads.
final class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String
    private var offered = false

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(.password) else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(
                username: username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
        )
    }
}

// MARK: - User-auth delegate: no-auth / fallback

// @unchecked Sendable: stateless, so capturing it across the channel
// initializer's @Sendable closure is inherently safe.
final class NoAuthDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        nextChallengePromise.succeed(nil)
    }
}

// MARK: - Host-key validation (accept-all)

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        // Mirrors ConnectionProfile.strictHostKeyChecking = false (the default).
        // TODO: implement real known-hosts checking when strictHostKeyChecking is true.
        validationCompletePromise.succeed(())
    }
}

// MARK: - Shell activation handler

/// Sits at the front of the child-channel pipeline, fires a PTY request when
/// the channel becomes active, waits for the server's reply, THEN fires a
/// ShellRequest and waits for its reply before removing itself so
/// ShellReadHandler takes over.
///
/// The two requests are deliberately serialized rather than fired back to
/// back. Real interactive clients (OpenSSH, Paramiko/Netmiko) request a PTY
/// with a reply, block until the server confirms it, and only then request
/// the shell. Some devices — particularly old Cisco IOS crypto images, like
/// the classic C7200 — run a fragile, effectively single-threaded vty/SSH
/// handler that can drop the connection outright if a shell request arrives
/// before it has finished processing the preceding pty-req (which, with
/// TCP_NODELAY and no synchronization, could previously land in the same
/// TCP segment). Waiting for the real round-trip reply — not a fixed sleep —
/// is what actually reproduces OpenSSH's timing here.
private final class ShellActivationHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn  = SSHChannelData
    typealias InboundOut = SSHChannelData

    private enum Stage {
        case awaitingPTYReply
        case awaitingShellReply
    }

    private let activationPromise: EventLoopPromise<Void>
    private var stage = Stage.awaitingPTYReply

    init(activationPromise: EventLoopPromise<Void>) {
        self.activationPromise = activationPromise
    }

    func channelActive(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "vt100",
                terminalCharacterWidth: 80,
                terminalRowHeight: 24,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: .init([:])
            ),
            promise: nil
        )
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch (stage, event) {
        case (.awaitingPTYReply, is ChannelSuccessEvent):
            stage = .awaitingShellReply
            context.triggerUserOutboundEvent(
                SSHChannelRequestEvent.ShellRequest(wantReply: true),
                promise: nil
            )
        case (.awaitingPTYReply, is ChannelFailureEvent):
            activationPromise.fail(
                SwiftmikoError.connectionFailed("SSH PTY request was rejected by the server")
            )
        case (.awaitingShellReply, is ChannelSuccessEvent):
            activationPromise.succeed(())
            context.pipeline.removeHandler(self, promise: nil)
        case (.awaitingShellReply, is ChannelFailureEvent):
            activationPromise.fail(
                SwiftmikoError.connectionFailed("SSH shell request was rejected by the server")
            )
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }
}

// MARK: - Shell read handler

/// Buffers all inbound SSHChannelData. Thread-safe: NIO event-loop threads
/// write into the buffer; Swift async tasks drain it.
private final class ShellReadHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn  = SSHChannelData
    typealias InboundOut = SSHChannelData

    private let lock = NSLock()
    private var buffer = ""

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(var bytes) = channelData.data else { return }
        guard let chunk = bytes.readString(length: bytes.readableBytes), !chunk.isEmpty else { return }
        lock.withLock { buffer += chunk }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    /// Drain and return all buffered data. Non-blocking.
    func drain() -> String {
        lock.withLock {
            let result = buffer
            buffer = ""
            return result
        }
    }
}

// MARK: - Pipeline error handler

private final class CloseOnErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - NIOSSHChannel

/// Real SSH transport conforming to the Swiftmiko Channel protocol.
///
/// Intended use via ChannelProvider:
/// ```swift
/// let provider: ChannelProvider = { profile in NIOSSHChannel(profile: profile) }
/// ```
public final class NIOSSHChannel: Swiftmiko.Channel, @unchecked Sendable {

    private let profile: ConnectionProfile
    private var parentNIOChannel: NIOCore.Channel?
    private var shellNIOChannel: NIOCore.Channel?
    private let readHandler = ShellReadHandler()

    public private(set) var isOpen = false

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    // MARK: Channel protocol

    public func open() async throws {
        let authDelegate = try makeAuthDelegate()
        let readHandler = self.readHandler

        let allowLegacyCiphers = profile.allowLegacyCiphers
        let bootstrap = ClientBootstrap(group: _swiftmikoNIOGroup)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let clientConfiguration: SSHClientConfiguration
                    if allowLegacyCiphers {
                        clientConfiguration = SSHClientConfiguration(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: AcceptAllHostKeysDelegate(),
                            globalRequestDelegate: nil,
                            transportProtectionSchemes: LegacyTransportProtection.schemesIncludingLegacyCBC
                        )
                    } else {
                        clientConfiguration = SSHClientConfiguration(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: AcceptAllHostKeysDelegate()
                        )
                    }
                    let sshHandler = NIOSSHHandler(
                        role: .client(clientConfiguration),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    let sync = channel.pipeline.syncOperations
                    try sync.addHandler(sshHandler)
                    try sync.addHandler(CloseOnErrorHandler())
                }
            }
            .connectTimeout(.seconds(Int64(profile.connectionTimeout)))
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)

        let parent: NIOCore.Channel
        do {
            parent = try await bootstrap.connect(host: profile.host, port: profile.port).get()
        } catch {
            throw SwiftmikoError.connectionFailed(
                "TCP connect to \(profile.host):\(profile.port) failed: \(error)"
            )
        }

        let shell: NIOCore.Channel
        do {
            shell = try await openShellChannel(on: parent, readHandler: readHandler)
        } catch let error as SwiftmikoError {
            _ = try? await parent.close().get()
            throw error
        } catch {
            _ = try? await parent.close().get()
            throw SwiftmikoError.connectionFailed(
                "Could not open SSH shell on \(profile.host): \(error)"
            )
        }

        parentNIOChannel = parent
        shellNIOChannel  = shell
        isOpen           = true
    }

    /// No-op: authentication is handled inside open() via the NIO SSH delegate.
    public func authenticate(username: String, using method: AuthMethod) async throws {}

    public func write(_ data: String) async throws {
        guard isOpen, let shell = shellNIOChannel else {
            throw SwiftmikoError.channelClosed
        }
        var buf = shell.allocator.buffer(capacity: data.utf8.count)
        buf.writeString(data)
        try await shell.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buf))).get()
    }

    public func readAvailable() async throws -> String {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        return readHandler.drain()
    }

    public func close() async {
        isOpen = false
        if let shell = shellNIOChannel {
            try? await shell.close().get()
        }
        if let parent = parentNIOChannel {
            try? await parent.close().get()
        }
        shellNIOChannel  = nil
        parentNIOChannel = nil
    }

    // MARK: Private helpers

    private func makeAuthDelegate() throws -> any NIOSSHClientUserAuthenticationDelegate & Sendable {
        switch profile.auth {
        case .password(let password):
            return PasswordAuthDelegate(username: profile.username, password: password)
        case .keyFile(let path, let passphrase):
            let nioKey = try SSHKeyLoader.load(path: path, passphrase: passphrase)
            return KeyAuthDelegate(username: profile.username, nioKey: nioKey)
        case .sshAgent:
            // SSH-agent forwarding is not supported by swift-nio-ssh.
            return NoAuthDelegate()
        case .none:
            return NoAuthDelegate()
        }
    }

    private func openShellChannel(
        on parent: NIOCore.Channel,
        readHandler: ShellReadHandler
    ) async throws -> NIOCore.Channel {
        try await parent.pipeline
            .handler(type: NIOSSHHandler.self)
            .flatMap { sshHandler -> EventLoopFuture<NIOCore.Channel> in
                // Create activationPromise inside the flatMap so it is only
                // allocated after handler(type:) succeeds. If that future fails
                // the flatMap is never entered and there is nothing to leak.
                let activationPromise = parent.eventLoop.makePromise(of: Void.self)
                let childPromise = parent.eventLoop.makePromise(of: NIOCore.Channel.self)
                sshHandler.createChannel(childPromise, channelType: .session) { child, type in
                    guard type == .session else {
                        activationPromise.fail(
                            SwiftmikoError.connectionFailed("Expected a session channel")
                        )
                        return child.eventLoop.makeFailedFuture(
                            SwiftmikoError.connectionFailed("Expected a session channel")
                        )
                    }
                    return child.eventLoop.makeCompletedFuture {
                        let sync = child.pipeline.syncOperations
                        try sync.addHandler(
                            ShellActivationHandler(activationPromise: activationPromise)
                        )
                        try sync.addHandler(readHandler)
                    }
                }
                // If the child-channel initializer threw before ShellActivationHandler
                // was added, activationPromise will never be signalled — fail it here
                // so it doesn't leak while the error propagates.
                return childPromise.futureResult
                    .flatMapError { error in
                        activationPromise.fail(error)
                        return parent.eventLoop.makeFailedFuture(error)
                    }
                    .flatMap { child in
                        activationPromise.futureResult.map { child }
                    }
            }
            .get()
    }
}

// MARK: - Default channel provider

/// The default ChannelProvider used by SSHDispatcher when no explicit channel
/// or provider is configured on a connection. Returns a NIOSSHChannel backed
/// by the shared event loop group.
public let nioSSHChannelProvider: ChannelProvider = { profile in
    NIOSSHChannel(profile: profile)
}
