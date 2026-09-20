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
//  Untitled.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//
// CiscoWLC.swift
public class CiscoWlcSSH: BaseConnection {

    // Called during the connection phase, before sessionPreparation.
    // Handles WLC's non-standard login banner sequence.
    func specialLoginHandler() async throws {
        let promptPattern = #"(?m:[>#]\s*$)"#
        let pattern = #"(?:User:|login as|ssword|(?m:[>#]\s*$))"#

        loginLoop: while true {
            let newData = try await readUntilPattern(pattern: pattern, timeout: 25.0)

            // Prompt detected — we're in
            if newData.range(of: promptPattern, options: .regularExpression) != nil {
                return
            }

            if newData.contains("User:") || newData.contains("login as") {
                try await writeChannel(profile.username + profile.returnCharacter)
            } else if newData.contains("ssword") {
                guard let password = profile.passwordString else {
                    throw SwiftmikoError.authenticationFailed("No password provided for WLC")
                }
                try await writeChannel(password + profile.returnCharacter)
            } else {
                throw SwiftmikoError.authenticationFailed(
                    "Failed to login to Cisco WLC — unexpected pattern in: \(newData)"
                )
            }
        }
    }
}
