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
// Sources/Swiftmiko/Keymile/KeymileNos.swift

import Foundation

/// Keymile NOS SSH driver.
///
/// Maps to netmiko's KeymileNOSSSH(CiscoIOSBase).
///
/// Inherits from CiscoIOSBase directly — a cross-vendor
/// inheritance relationship, same category as Cisco APIC's LinuxSSH
/// lineage, except here it's genuinely reusing IOS's own driver
/// logic rather than a generic Cisco base class.
///
/// The defining quirk: Keymile NOS's SSH server always reports a
/// successful connection at the transport level, regardless of
/// whether the credentials were actually valid — the real
/// authentication outcome only shows up as text in the channel
/// output AFTER the connection appears to succeed. This forces
/// authentication-failure detection down into testChannelRead()
/// itself, since that's the earliest point any real signal is
/// available.
public final class KeymileNOSSSH: CiscoIOSBase {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    override public func sessionPreparation() async throws {
        try await setBasePrompt()
        try await disablePaging()
        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Channel Read Override

    /// Read from the channel, checking for Keymile's delayed
    /// authentication-failure signal.
    ///
    /// Maps to netmiko's _test_channel_read(count=40, pattern="").
    ///
    /// Since paramiko.connect() always reports success on this
    /// platform regardless of actual credential validity, this is the
    /// earliest point a real "Login incorrect" signal can be detected
    /// — checked on EVERY testChannelRead() call, not just once
    /// during login, since Netmiko's own implementation doesn't
    /// special-case which call site this runs from. On detection,
    /// this actively tears down the underlying Paramiko connection
    /// before throwing, mirroring Fiberstore FSOS's and Huawei ONT
    /// Telnet's "clean up before failing" discipline.
    override public func testChannelRead(
        count: Int = 40,
        pattern: String = ""
    ) async throws -> String {
        let output = try await super.testChannelRead(count: count, pattern: pattern)

        if output.range(of: "Login incorrect", options: .regularExpression) != nil {
            await closeTransport()
            throw SwiftmikoError.authenticationFailed(
                "Authentication failure: unable to connect" +
                "\(profile.deviceType) \(profile.host):\(profile.port)" +
                responseReturn + "Login incorrect"
            )
        }
        return output
    }

    // MARK: Login Handling

    /// Wait for either the normal prompt or the delayed
    /// authentication-failure message.
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// Delegates entirely to the overridden testChannelRead() above —
    /// the failure detection happens there regardless of which
    /// pattern this call was waiting for, so this method's own job is
    /// just to wait for the RIGHT pattern; the wrong-credential case
    /// is caught as a side effect either way.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        _ = try await testChannelRead(pattern: "(>|Login incorrect)")
    }
}
