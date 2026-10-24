// Examples/RedispatchDemo/RedispatchViewModel.swift
//
// The "bounce through a terminal server onto a different device type"
// pattern from EXAMPLES.md's "Terminal server and redispatch" section,
// as a runnable single-hop demo: connect normally to a first device,
// telnet from its own CLI to a terminal server without reconnecting,
// then redispatch() to swap the active driver onto the SAME channel
// for whatever's actually attached on the other side.

import Foundation
import Swiftmiko

@MainActor
@Observable
final class RedispatchViewModel {
    var host = ""
    var username = ""
    var password = ""
    var firstDeviceType = "cisco_ios"

    var terminalServerHost = ""

    var finalDeviceType = "cisco_ios"
    var finalCommand = "show version"

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    var steps: [RedispatchStep] = []
    var isRunning = false
    var errorMessage: String?

    func runSequence() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        steps = [
            RedispatchStep(label: "Connect to \(firstDeviceType) at \(host)"),
            RedispatchStep(label: "Telnet to terminal server at \(terminalServerHost)"),
            RedispatchStep(label: "Redispatch to \(finalDeviceType)"),
            RedispatchStep(label: "Run \"\(finalCommand)\""),
        ]

        do {
            steps[0].status = .running
            let profile = ConnectionProfile(
                host: host,
                deviceType: firstDeviceType,
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            var connection = try await SSHDispatcher.connectHandler(profile: profile)
            steps[0].status = .done

            // telnetLogin() has no separate username/password
            // parameters of its own — it always authenticates with
            // whatever's on the CURRENT connection's profile, so the
            // terminal server needs the same credentials as the first
            // device for this to work as written. A terminal server
            // needing different credentials isn't something this
            // particular call can express; it's a real constraint of
            // the API, not something this demo works around.
            steps[1].status = .running
            try await connection.writeChannel("telnet \(terminalServerHost)\n")
            steps[1].output = try await connection.telnetLogin()
            steps[1].status = .done

            steps[2].status = .running
            connection = try await SSHDispatcher.redispatch(connection, deviceType: finalDeviceType)
            steps[2].status = .done

            steps[3].status = .running
            steps[3].output = try await connection.sendCommand(finalCommand, readTimeout: 30.0)
            steps[3].status = .done

            await connection.disconnect()
        } catch {
            errorMessage = error.localizedDescription
            if let runningIndex = steps.firstIndex(where: { $0.status == .running }) {
                steps[runningIndex].status = .failed
                steps[runningIndex].output = error.localizedDescription
            }
        }
    }
}
