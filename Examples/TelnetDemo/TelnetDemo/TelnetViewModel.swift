// Examples/TelnetDemo/TelnetViewModel.swift
import Foundation
import Swiftmiko

@MainActor
@Observable
final class TelnetViewModel {
    var host = ""
    var port = 23
    var username = ""
    var password = ""
    var secret = ""

    var command = "show version"

    var output = ""
    var isRunning = false
    var errorMessage: String?

    func connectRunAndDisconnect() async {
        errorMessage = nil
        output = ""
        isRunning = true
        defer { isRunning = false }

        do {
            // "cisco_ios_telnet" is what routes SSHDispatcher.connectHandler()
            // to a Telnet transport (NIOTelnetChannel) instead of SSH — the
            // device type's "_telnet" suffix is what selects it, same as
            // real Netmiko. Telnet has no notion of a cipher suite: it's
            // plaintext on the wire, so only use this against lab gear on a
            // trusted network.
            let profile = ConnectionProfile(
                host: host,
                port: port,
                deviceType: "cisco_ios_telnet",
                username: username,
                auth: .password(password),
                secret: secret.isEmpty ? nil : secret
            )
            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            defer { Task { await connection.disconnect() } }

            if !secret.isEmpty {
                try await connection.enterEnableMode(secret: secret)
            }

            output = try await connection.sendCommand(command, readTimeout: 30.0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
