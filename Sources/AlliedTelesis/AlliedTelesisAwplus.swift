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
// Sources/Swiftmiko/AlliedTelesis/AlliedTelesisAwplus.swift

import Foundation

/// Common implementation for Allied Telesis AlliedWare Plus devices.
///
/// Maps to netmiko's AlliedTelesisAwplusBase(CiscoBaseConnection).
open class AlliedTelesisAwplusBase: CiscoBaseConnection {

    // MARK: Session Preparation

    /// Disable paging (the "--more--" prompts) and detect the base
    /// prompt.
    ///
    /// Maps to netmiko's:
    ///     self.disable_paging()
    ///     self.set_base_prompt()
    ///     time.sleep(0.3 * self.global_delay_factor)
    override public func sessionPreparation() async throws {
        try await disablePaging()
        try await setBasePrompt()
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    // MARK: Shell Access

    /// Enter the underlying Bourne shell.
    ///
    /// Maps to netmiko's _enter_shell(). Internal rather than
    /// private — unlike Nodegrid's equivalent, there's no paired
    /// SCPHandler subclass in this file that needs it, but it's kept
    /// at module (not private) visibility in case a future
    /// AlliedTelesisAwplusFileTransfer or a diagnostic caller within
    /// Swiftmiko needs it directly, matching the leading-underscore
    /// "module-internal, not truly private" intent of the Python
    /// source.
    @discardableResult
    internal func enterShell() async throws -> String {
        return try await sendCommand(
            "start shell sh",
            expectString: #"[\$#]"#
        )
    }

    /// Return to the AlliedWare Plus CLI from the Bourne shell.
    /// Maps to netmiko's _return_cli().
    @discardableResult
    internal func returnCLI() async throws -> String {
        return try await sendCommand(
            "exit",
            expectString: "[#>]"
        )
    }

    // MARK: Config Mode

    /// Exit configuration mode, handling uncommitted changes.
    ///
    /// Maps to netmiko's exit_config_mode(exit_config="exit").
    ///
    /// If there are uncommitted changes, the device asks "Exit with
    /// uncommitted changes?" — this always answers "yes", the same
    /// discard-and-exit policy used by every other driver in this
    /// vendor set that hits an equivalent confirmation prompt
    /// (Viptela, Yamaha, ALAXALA). Saving remains the caller's
    /// explicit responsibility.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        var output = ""
        guard try await isInConfigMode() else { return output }

        output += try await sendCommandTiming(
            exitConfig,
            stripPrompt: false,
            stripCommand: false
        )

        if output.contains("Exit with uncommitted changes?") {
            output += try await sendCommandTiming(
                "yes",
                stripPrompt: false,
                stripCommand: false
            )
        }

        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed(
                "Failed to exit configuration mode"
            )
        }
        return output
    }
}

// MARK: - AlliedTelesisAwplusSSH

/// Allied Telesis AlliedWare Plus SSH driver — no differences from
/// the base.
/// Maps to netmiko's AlliedTelesisAwplusSSH(AlliedTelesisAwplusBase).
public final class AlliedTelesisAwplusSSH: AlliedTelesisAwplusBase {}
