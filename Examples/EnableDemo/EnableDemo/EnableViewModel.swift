// Examples/EnableDemo/EnableViewModel.swift
import Foundation
import Swiftmiko
import Combine

@MainActor
final class EnableViewModel: ObservableObject {
    @Published var host = "cisco1.lasthop.io"
    @Published var username = "pyclass"
    @Published var password = ""
    @Published var secret = ""

    @Published var prompt: String?
    @Published var errorMessage: String?
    @Published var isConnecting = false

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    func connectAndEnable() async {
        isConnecting = true
        errorMessage = nil
        prompt = nil
        defer { isConnecting = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "cisco_ios",
                username: username,
                auth: .password(password),
                secret: secret,
                allowLegacyCiphers: allowLegacyCiphers
            )

            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            defer { Task { await connection.disconnect() } }

            // Equivalent of Netmiko's net_connect.enable()
            try await connection.enterEnableMode(secret: secret)

            // Equivalent of Netmiko's net_connect.find_prompt()
            prompt = try await connection.findPrompt()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
