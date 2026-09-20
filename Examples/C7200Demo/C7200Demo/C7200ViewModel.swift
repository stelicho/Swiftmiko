// Examples/C7200Demo/C7200ViewModel.swift
import AppKit
import Foundation
import Observation
import Swiftmiko

@MainActor
@Observable
final class C7200ViewModel {
    var host = ""
    var username = ""
    var password = ""
    var secret = ""

    var steps: [RouterStep] = [
        RouterStep(label: "Version", command: "show version"),
        RouterStep(label: "Privilege Level", command: "show privilege"),
        RouterStep(label: "Running Config", command: "show running-config"),
    ]

    var isRunning = false
    var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support, like an old C7200
    /// IOS image.
    var allowLegacyCiphers = false

    /// Older IOS on a C7200 can genuinely take a while to return a
    /// large running-config — a much longer timeout than the modern
    /// IOS-XE examples used, since classic IOS platforms are slower
    /// and have no guarantee of fast terminal negotiation.
    private let readTimeout: TimeInterval = 90.0

    var runningConfig: String {
        steps.first(where: { $0.command == "show running-config" })?.output ?? ""
    }

    func runSequence() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        for index in steps.indices {
            steps[index].output = ""
            steps[index].status = .pending
        }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "cisco_ios",
                username: username,
                auth: .password(password),
                secret: secret.isEmpty ? nil : secret,
                // C7200s in a lab are frequently slow to bring up a
                // session at all — give connection and auth more
                // room than the defaults before giving up.
                connectionTimeout: 30,
                readTimeout: readTimeout,
                allowLegacyCiphers: allowLegacyCiphers
            )

            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            defer { Task { await connection.disconnect() } }

            if !secret.isEmpty {
                try await connection.enterEnableMode(secret: secret)
            }

            // Run the whole sequence on the SAME connection, in
            // order — a real terminal session doing a few show
            // commands back to back, not a fresh connection per
            // command.
            for index in steps.indices {
                steps[index].status = .running
                do {
                    let result = try await connection.sendCommand(
                        steps[index].command,
                        readTimeout: readTimeout
                    )
                    steps[index].output = result
                    steps[index].status = .done
                } catch {
                    steps[index].output = error.localizedDescription
                    steps[index].status = .failed
                    // Stop the sequence on first failure rather than
                    // continuing to run commands against a session
                    // that may already be in a bad state.
                    throw error
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveRunningConfig() {
        guard !runningConfig.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(host)-running-config.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? self.runningConfig.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
