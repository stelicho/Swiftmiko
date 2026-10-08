// Examples/UbiquitiDemo/UbiquitiViewModel.swift
import Foundation
import Swiftmiko
import Combine

@MainActor
final class UbiquitiViewModel: ObservableObject {
    @Published var platform: UbiquitiPlatform = .unifiSwitch {
        didSet {
            // Reset the command selection whenever the platform
            // changes, since the previous platform's commands don't
            // apply to the new one.
            selectedCommand = platform.commands.first
        }
    }

    @Published var host = ""
    @Published var username = ""
    @Published var password = ""
    @Published var secret = ""

    @Published var selectedCommand: CommonCommand?
    @Published var customCommand: String = ""
    @Published var useCustomCommand: Bool = false

    @Published var output: String = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    private var connection: BaseConnection?

    var isConnected: Bool { connection != nil }

    var effectiveCommand: String {
        useCustomCommand ? customCommand : (selectedCommand?.command ?? "")
    }

    init() {
        selectedCommand = platform.commands.first
    }

    func connect() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: platform.rawValue,
                username: username,
                auth: .password(password),
                secret: secret.isEmpty ? nil : secret,
                allowLegacyCiphers: allowLegacyCiphers
            )
            // SSHDispatcher.connectHandler wires in the NIOSSH channel
            // provider registered for each ubiquiti_* device_type and
            // connects — this already runs UnifiSwitchSSH's
            // "telnet localhost" session setup, EdgeSwitch's enable
            // sequence, or EdgeRouter's VyOS-style prep, whichever
            // the selected platform maps to.
            let newConnection = try await SSHDispatcher.connectHandler(profile: profile)

            // Only run enterEnableMode on platforms that actually
            // support it — EdgeRouter (VyOS-based) has no privilege
            // level to escalate to.
            if platform.supportsEnableMode, !secret.isEmpty {
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
