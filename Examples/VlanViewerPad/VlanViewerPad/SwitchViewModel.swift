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
//  Examples/VlanViewerPad/SwitchViewModel.swift

import Combine
import Foundation
import Swiftmiko

@MainActor
final class SwitchViewModel: ObservableObject {
    @Published var vlans: [VlanEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var host = ""
    @Published var username = ""
    @Published var password = ""

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    func fetchVlans() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "cisco_ios",   // IOS-XE uses the IOS driver family
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )

            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            defer { Task { await connection.disconnect() } }

            let output = try await connection.sendCommand("show vlan brief")
            vlans = VlanBriefParser.parse(output)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
