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
// Sources/Swiftmiko/Dell/DellForce10.swift

import Foundation

/// Dell Force10 SSH driver, supporting DNOS9.
///
/// Maps to netmiko's DellForce10SSH(CiscoSSHConnection).
public final class DellForce10SSH: CiscoSSHConnection {

    override public nonisolated var promptPattern: String { "[>#]" }

    // MARK: Session Preparation

    /// Check for and acknowledge a login banner, then prepare the
    /// session normally.
    ///
    /// Maps to netmiko's session_preparation().
    ///
    /// If "banner login acknowledge enable" is configured on the
    /// device, it presents a yes/no confirmation before allowing
    /// login to complete:
    ///
    ///     Have you read and do you acknowledge the above statement? [y/n]: y
    ///     switch>
    ///
    /// This waits for either that y/n prompt or the normal device
    /// prompt, and answers "y" if the banner prompt appeared.
    override public func sessionPreparation() async throws {
        let data = try await readUntilPattern(pattern: "y/n|\(promptPattern)")

        if data.range(of: "y/n", options: .regularExpression) != nil {
            try await writeChannel("y" + profile.returnCharacter)
        }

        try await setBasePrompt()
        try await setTerminalWidth()
        try await disablePaging()
    }

    // MARK: Config Mode

    /// Maps to netmiko's check_config_mode(check_string=")#",
    /// pattern=prompt_pattern).
    override public func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="write memory").
    override public func saveConfig(
        command: String = "write memory",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await super.saveConfig(
            command: command,
            confirm: confirm,
            confirmResponse: confirmResponse
        )
    }
}
