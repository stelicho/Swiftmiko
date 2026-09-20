// Examples/CommandRunnerDemo/CommandRunnerViewModel.swift
import Foundation
import Swiftmiko

@MainActor
@Observable
final class CommandRunnerViewModel {
    var host = ""
    var username = ""
    var password = ""
    var secret = ""

    var selectedCommand: CommonCommand = CommonCommand.library[0]
    var customCommand = ""
    var useCustomCommand = false

    var output = ""
    var isRunning = false
    var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    private var connection: BaseConnection?

    var isConnected: Bool { connection != nil }

    var effectiveCommand: String {
        useCustomCommand ? customCommand : selectedCommand.command
    }

    func connect() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "cisco_ios",
                username: username,
                auth: .password(password),
                secret: secret.isEmpty ? nil : secret,
                allowLegacyCiphers: allowLegacyCiphers
            )
            let newConnection = try await SSHDispatcher.connectHandler(profile: profile)

            if !secret.isEmpty {
                try await newConnection.enterEnableMode(secret: secret)
            }
            connection = newConnection
        } catch {
            errorMessage = error.localizedDescription
            connection = nil
        }
    }

    func runCommand() async {
        guard let connection else {
            errorMessage = "Not connected — press Connect first."
            return
        }
        guard !effectiveCommand.isEmpty else { return }

        errorMessage = nil
        isRunning = true
        output = ""
        defer { isRunning = false }

        do {
            output = try await connection.sendCommand(effectiveCommand, readTimeout: 30.0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await connection?.disconnect()
        connection = nil
        output = ""
    }
}
