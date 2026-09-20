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
// Sources/Swiftmiko/Eltex/EltexEsr.swift

import Foundation

/// Eltex ESR (Enterprise Service Router) SSH driver.
///
/// Maps to netmiko's EltexEsrSSH(CiscoSSHConnection).
///
/// Uses a commit-based configuration model with a genuinely richer
/// lifecycle than most commit-based drivers seen so far: beyond a
/// plain commit(), ESR also supports confirming a commit
/// (presumably to make a provisional change permanent) and restoring
/// a previous configuration from backup if something goes wrong.
public final class EltexEsrSSH: CiscoSSHConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — identical structure
    /// to the plain EltexSSH driver above.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await disablePaging(command: "terminal datadump")
    }

    // MARK: Config Mode

    /// Maps to netmiko's config_mode(config_command="configure",
    /// pattern=r"\)\#").
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure",
        pattern: String = #")#"#,
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern
        )
    }

    /// Maps to netmiko's check_config_mode(check_string="(config").
    /// Note the deliberately unbalanced parenthesis in the check
    /// string — matching just the opening "(config" substring,
    /// regardless of which specific sub-mode follows it
    /// (config-if, config-router, etc.), rather than requiring an
    /// exact closing bracket shape.
    override public func isInConfigMode(
        checkString: String = "(config",
        pattern: String = ""
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Not supported — use commit() instead.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Eltex ESR does not use saveConfig() — call commit() instead"
        )
    }

    // MARK: Commit Lifecycle

    /// Commit the candidate configuration.
    ///
    /// Maps to netmiko's commit(read_timeout=120.0).
    ///
    /// Always exits config mode first if currently in it, before
    /// sending the bare "commit" command — unlike CDOT CROS's
    /// equivalent, which enters config mode as part of the commit
    /// sequence, Eltex ESR apparently expects commit to be issued
    /// from OUTSIDE config mode. Failure is detected by scanning for
    /// a fixed error-marker string in the response.
    @discardableResult
    public func commit(readTimeout: TimeInterval = 120.0) async throws -> String {
        let errorMarker = "Can't commit configuration"

        if try await isInConfigMode() {
            _ = try await exitConfigMode()
        }

        let output = try await sendCommand("commit", readTimeout: readTimeout)

        guard !output.contains(errorMarker) else {
            throw SwiftmikoError.commandFailed(
                "Commit failed with following errors:\n\n\(output)"
            )
        }
        return output
    }

    /// Confirm a previously committed candidate configuration.
    ///
    /// Maps to netmiko's _confirm(read_timeout=120.0).
    ///
    /// Internal, not private — matches Netmiko's leading-underscore
    /// "advanced/manual use" convention, same treatment as
    /// Asterfusion's enterVtysh(). The exact relationship between
    /// commit() and confirm() on this platform (e.g. whether ESR
    /// implements a rollback-on-timeout style two-stage commit,
    /// similar in spirit to some routers' "commit confirmed" pattern)
    /// isn't fully explained by this file alone — worth checking
    /// Eltex's own CLI documentation before assuming the exact
    /// semantics.
    @discardableResult
    internal func confirmCommit(readTimeout: TimeInterval = 120.0) async throws -> String {
        let errorMarker = "Nothing to confirm in configuration"

        if try await isInConfigMode() {
            _ = try await exitConfigMode()
        }

        let output = try await sendCommand("confirm", readTimeout: readTimeout)

        guard !output.contains(errorMarker) else {
            throw SwiftmikoError.commandFailed(
                "Confirm failed with following errors:\n\n\(output)"
            )
        }
        return output
    }

    /// Restore a previous configuration from backup.
    ///
    /// Maps to netmiko's _restore(read_timeout=120.0).
    ///
    /// Same internal visibility and structural pattern as
    /// confirmCommit() above — a rescue mechanism for when a commit
    /// went wrong, restoring from whatever backup the device keeps
    /// automatically around a commit operation.
    @discardableResult
    internal func restoreConfig(readTimeout: TimeInterval = 120.0) async throws -> String {
        let errorMarker = "Can't find backup of previous configuration!"

        if try await isInConfigMode() {
            _ = try await exitConfigMode()
        }

        let output = try await sendCommand("restore", readTimeout: readTimeout)

        guard !output.contains(errorMarker) else {
            throw SwiftmikoError.commandFailed(
                "Restore failed with following errors:\n\n\(output)"
            )
        }
        return output
    }
}
