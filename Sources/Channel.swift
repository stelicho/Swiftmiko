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
//  Channel.swift
//  Swiftmiko
//
//  Transport-neutral interactive channel used by BaseConnection.
//

import Foundation

/// Authentication methods supported by a Swiftmiko channel.
public enum AuthMethod: Sendable {
    case password(String)
    case keyFile(path: String, passphrase: String? = nil)
    case sshAgent
    case none
}

/// A connected, interactive device channel.
///
/// Swiftmiko's connection logic only needs these operations. SwiftNIO SSH,
/// Telnet, serial-console, and test transports can implement this protocol
/// independently.
public protocol Channel: AnyObject, Sendable {
    var isOpen: Bool { get }

    func open() async throws
    func authenticate(username: String, using method: AuthMethod) async throws
    func write(_ data: String) async throws
    func readAvailable() async throws -> String
    func close() async
}

/// In-memory channel useful for unit tests and protocol-level simulations.
public final class BufferedChannel: Channel, @unchecked Sendable {
    public private(set) var isOpen = false
    public private(set) var writes: [String] = []

    private var pendingOutput = ""
    private var authenticationError: Error?

    public init(
        initialOutput: String = "",
        authenticationError: Error? = nil
    ) {
        self.pendingOutput = initialOutput
        self.authenticationError = authenticationError
    }

    public func open() async throws {
        isOpen = true
    }

    public func authenticate(
        username: String,
        using method: AuthMethod
    ) async throws {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        if let authenticationError {
            throw authenticationError
        }
    }

    public func write(_ data: String) async throws {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        writes.append(data)
    }

    public func readAvailable() async throws -> String {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        let output = pendingOutput
        pendingOutput = ""
        return output
    }

    public func close() async {
        isOpen = false
    }

    /// Queue data that should be returned by the next read.
    public func enqueueOutput(_ output: String) {
        pendingOutput += output
    }
}
