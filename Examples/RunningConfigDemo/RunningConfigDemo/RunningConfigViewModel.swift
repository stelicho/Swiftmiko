// Examples/RunningConfigDemo/RunningConfigViewModel.swift
import Foundation
import Swiftmiko

@MainActor
final class RunningConfigViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""
    @Published var secret = ""

    @Published var runningConfig: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    func fetchRunningConfig() async {
        isLoading = true
        errorMessage = nil
        runningConfig = ""
        defer { isLoading = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "cisco_ios",
                username: username,
                auth: .password(password),
                secret: secret.isEmpty ? nil : secret,
                allowLegacyCiphers: allowLegacyCiphers
            )

            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            defer { Task { await connection.disconnect() } }

            if !secret.isEmpty {
                try await connection.enterEnableMode(secret: secret)
            }

            // "show running-config" is long and paginated by default;
            // disablePaging() already ran during sessionPreparation(),
            // so this should come back as one clean block of text.
            runningConfig = try await connection.sendCommand(
                "show running-config",
                readTimeout: 60.0
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(host)-running-config.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? self.runningConfig.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
