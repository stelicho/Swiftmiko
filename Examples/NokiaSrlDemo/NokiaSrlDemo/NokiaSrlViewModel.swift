// Examples/NokiaSrlDemo/NokiaSrlViewModel.swift
import Foundation
import Swiftmiko

@MainActor
@Observable
final class NokiaSrlViewModel {
    var host = ""
    var port = 22
    var username = ""
    var password = ""

    // SR Linux has no privilege-escalation step at all — NokiaSrlSSH
    // conforms to NoEnable, so there's deliberately no "secret" field
    // here the way the Cisco IOS command runner has one.

    var selectedCommand: NokiaSrlCommand = NokiaSrlCommand.library[0]
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
                port: port,
                deviceType: "nokia_srl",
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            connection = try await SSHDispatcher.connectHandler(profile: profile)
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
