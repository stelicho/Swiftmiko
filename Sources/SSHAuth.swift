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
//  SSHAuth.swift
//  Swiftmiko
//
//  Port of netmiko/ssh_auth.py
//

import Foundation

/// Transport capable of performing SSH's "none" authentication request.
///
/// Paramiko exposes this through `Transport.auth_none`. Swiftmiko keeps the
/// operation behind a protocol so the concrete SwiftNIO SSH transport remains
/// replaceable.
public protocol SSHNoAuthTransport: AnyObject {
    func authenticateNone(username: String) async throws
}

/// SSH client used when Swiftmiko is handling authentication itself.
///
/// This is the Swift equivalent of Netmiko's `SSHClient_noauth`.
public final class SSHClientNoAuth {
    private let transport: SSHNoAuthTransport

    public init(transport: SSHNoAuthTransport) {
        self.transport = transport
    }

    /// Request no-authentication for `username`.
    public func authenticate(username: String) async throws {
        try await transport.authenticateNone(username: username)
    }
}

/// Compatibility spelling matching the original Python class name.
public typealias SSHClient_noauth = SSHClientNoAuth
