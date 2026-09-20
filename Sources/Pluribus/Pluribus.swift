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
// Sources/Swiftmiko/Pluribus/Pluribus.swift

import Foundation

/// Common methods for Pluribus Networks devices.
///
/// Maps to netmiko's PluribusSSH(NoConfig, BaseConnection).
///
/// No configuration mode via this connection — hence NoConfig.
public final class PluribusSSH: BaseConnection, NoConfig {

    /// Maps to netmiko's __init__ override:
    ///     super().__init__(*args, **kwargs)
    ///     self._config_mode = False
    ///
    /// Same direct internal-flag correction seen on F5 TMSH — this
    /// simply ensures the config-mode flag starts in a known false
    /// state, explicitly rather than relying on whatever
    /// BaseConnection's own default happens to be. Given NoConfig
    /// conformance already guarantees enterConfigMode()/
    /// exitConfigMode() are safe no-ops on this platform, this is
    /// mostly a belt-and-suspenders correctness measure rather than
    /// something strictly necessary — preserved faithfully anyway,
    /// matching the F5 TMSH precedent for reaching past the mode
    /// transition methods to correct the underlying flag directly.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        super.init(
            profile: profile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
        inConfigMode = false
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        _ = try await testChannelRead()
        try await setBasePrompt()
        try await disablePaging()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Paging

    /// Maps to netmiko's disable_paging(command="pager off").
    @discardableResult
    override public func disablePaging(
        command: String = "pager off",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.disablePaging(
            command: command,
            cmdVerify: cmdVerify,
            pattern: pattern
        )
    }
}
