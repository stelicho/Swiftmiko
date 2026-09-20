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
//  Exceptions.swift
//  Swiftmiko
//

import Foundation

public enum SwiftmikoError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case authenticationFailed(String)
    case timeout(String)
    case noConnection
    case configModeNotSupported
    case unexpectedPrompt(String)
    case commandFailed(String)
    case invalidArgument(String)
    case notImplemented(String)
    case channelClosed
    // New — flagged during TelnetProxy review and various SCP drivers.
    case alreadyConnected
    case scpTransferFailed(String)
    case promptDetectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message),
             .authenticationFailed(let message),
             .timeout(let message),
             .unexpectedPrompt(let message),
             .commandFailed(let message),
             .invalidArgument(let message),
             .notImplemented(let message),
             .scpTransferFailed(let message),
             .promptDetectionFailed(let message):
            return message
        case .noConnection:
            return "The connection is not open"
        case .configModeNotSupported:
            return "Configuration mode is not supported by this device"
        case .channelClosed:
            return "The channel is closed"
        case .alreadyConnected:
            return "This transport is already connected"
        }
    }
}

public typealias ConnectionException = SwiftmikoError
public typealias SwiftmikoTimeoutException = SwiftmikoError
public typealias SwiftmikoAuthenticationException = SwiftmikoError
