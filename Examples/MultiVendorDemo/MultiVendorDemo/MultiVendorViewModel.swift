// Examples/MultiVendorDemo/MultiVendorViewModel.swift
import Foundation
import Swiftmiko
import Combine

@MainActor
final class MultiVendorViewModel: ObservableObject {
    @Published var platform: DevicePlatform = .ciscoIOS {
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
            let newConnection = try await SSHDispatcher.connectHandler(profile: profile)

            // Only run enable() on platforms that actually support it —
            // Juniper and Fortinet are NoEnable drivers, and calling
            // enterEnableMode on them would just throw notImplemented.
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
