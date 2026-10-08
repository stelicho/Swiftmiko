// Examples/LinuxDemo/LinuxViewModel.swift
import Combine
import Foundation
import Swiftmiko

@MainActor
final class LinuxViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""

    /// A plain Linux box has no "enable mode" — sudo is the closest
    /// equivalent, and LinuxSSHConnection maps enterConfigMode() to
    /// "sudo -s" internally. Leave empty for a VM with no sudo password
    /// (e.g. passwordless sudo, or testing as a non-privileged user).
    @Published var sudoPassword = ""

    @Published var selectedCommand: LinuxCommand = LinuxCommand.library[0]
    @Published var customCommand = ""
    @Published var useCustomCommand = false

    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

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
                deviceType: "linux",
                username: username,
                auth: .password(password),
                secret: sudoPassword.isEmpty ? nil : sudoPassword,
                allowLegacyCiphers: allowLegacyCiphers
            )

            // SSHDispatcher.connectHandler wires in the NIOSSH channel
            // provider registered for "linux" and connects.
            let newConnection = try await SSHDispatcher.connectHandler(profile: profile)

            // Escalate to root via "sudo -s" if a sudo password was given.
            // Most distros' default user can already run plenty of
            // diagnostics without this, so it's optional here.
            if !sudoPassword.isEmpty {
                try await newConnection.enterConfigMode()
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
            output = try await connection.sendCommand(effectiveCommand, readTimeout: 20.0)
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
