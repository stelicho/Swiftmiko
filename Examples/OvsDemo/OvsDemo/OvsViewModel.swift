// Examples/OvsDemo/OvsViewModel.swift
import Combine
import Foundation
import Swiftmiko

@MainActor
final class OvsViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""

    /// OVS hosts are just Linux boxes — "enable mode" here is
    /// sudo, and this doubles as the sudo password. LinuxSSHConnection
    /// maps enterConfigMode() to "sudo -s" internally.
    @Published var sudoPassword = ""

    @Published var bridges: [OvsBridge] = []
    @Published var selectedCommand: OvsCommand = OvsCommand.library[0]
    @Published var customCommand = ""
    @Published var useCustomCommand = false

    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    private var connection: OvsLinuxSSH?

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
                deviceType: "ovs_linux",
                username: username,
                auth: .password(password),
                secret: sudoPassword.isEmpty ? nil : sudoPassword,
                allowLegacyCiphers: allowLegacyCiphers
            )

            // Constructed directly rather than via SSHDispatcher,
            // since OVS isn't yet wired into the dispatcher's
            // registry — this is also the more explicit pattern when
            // you already know the concrete driver you want.
            let newConnection = OvsLinuxSSH(profile: profile)
            try await newConnection.connect()

            // Escalate to root, needed for most ovs-vsctl/ovs-ofctl
            // commands. On LinuxSSHConnection this is "sudo -s", not
            // a Cisco-style "enable".
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

    func fetchTopology() async {
        guard let connection else {
            errorMessage = "Not connected — press Connect first."
            return
        }

        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let raw = try await connection.sendCommand("ovs-vsctl show", readTimeout: 20.0)
            output = raw
            bridges = OvsVsctlShowParser.parse(raw)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await connection?.disconnect()
        connection = nil
        output = ""
        bridges = []
    }
}
