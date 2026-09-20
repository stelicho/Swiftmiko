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
//  CiscoXR.swift
//  Swiftmiko
//
//  Created by KK Campbell on 9/3/26.
//
// CiscoXR.swift
import Foundation

public class CiscoXrBase: CiscoBaseConnection, NoEnable {

    // XR does not use save_config — use commit() instead
    override public func saveConfig(command: String = "",
                                    confirm: Bool = false,
                                    confirmResponse: String = "") async throws -> String {
        throw SwiftmikoError.notImplemented(
            "CiscoXR does not use saveConfig() — call commit() instead"
        )
    }

    // XR-specific commit with label/comment/confirm/replace options
    public func commit(
        confirm: Bool = false,
        confirmDelay: Int? = nil,
        comment: String = "",
        label: String = "",
        replace: Bool = false,
        readTimeout: TimeInterval = 120.0
    ) async throws -> String {
        // Build the commit command string from arguments
        var commandString = replace ? "commit replace" : "commit"
        if !label.isEmpty {
            commandString += " label \(label)"
        }
        if confirm, let delay = confirmDelay {
            commandString += " confirmed \(delay)"
        } else if !comment.isEmpty {
            commandString += " comment \(comment)"
        }
        // ...handle interactive prompts (large config, other commits)
        return try await sendCommand(commandString, readTimeout: readTimeout)
    }
}
