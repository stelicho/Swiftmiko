// Examples/FleetDemo/FleetViewModel.swift
//
// Runs the same command against several devices concurrently via
// withTaskGroup, rather than one at a time — the Swift-structured-
// concurrency counterpart to Netmiko Tools' ThreadPoolExecutor-based
// fan-out (see Sources/CLITools/SSHConn.swift's runDeviceTasks(), the
// same pattern applied there to swiftmiko-show/cfg/grep).

import Foundation
import Swiftmiko

@MainActor
@Observable
final class FleetViewModel {
    var devices: [FleetDevice] = [FleetDevice(), FleetDevice(), FleetDevice()]
    var username = ""
    var password = ""
    var command = "show version"

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    var results: [FleetDevice.ID: FleetResultState] = [:]
    var isRunning = false

    var activeDevices: [FleetDevice] {
        devices.filter { !$0.host.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func addDevice() {
        devices.append(FleetDevice())
    }

    func removeDevice(_ id: FleetDevice.ID) {
        devices.removeAll { $0.id == id }
        results[id] = nil
    }

    func runFleet() async {
        let targets = activeDevices
        guard !targets.isEmpty else { return }

        isRunning = true
        defer { isRunning = false }

        for device in targets {
            results[device.id] = .running
        }

        // Each child task only captures plain, Sendable values (never
        // `self`) and returns its result rather than mutating `results`
        // directly — `results[id] = state` only ever happens back on
        // this @MainActor-isolated method, as each child task finishes
        // and `for await` resumes here. That's what makes the UI update
        // one device at a time as results land, instead of all at once
        // at the end.
        let username = username
        let password = password
        let command = command
        let allowLegacyCiphers = allowLegacyCiphers

        await withTaskGroup(of: (FleetDevice.ID, FleetResultState).self) { group in
            for device in targets {
                group.addTask {
                    do {
                        let profile = ConnectionProfile(
                            host: device.host,
                            deviceType: device.deviceType,
                            username: username,
                            auth: .password(password),
                            allowLegacyCiphers: allowLegacyCiphers
                        )
                        let connection = try await SSHDispatcher.connectHandler(profile: profile)
                        let output = try await connection.sendCommand(command, readTimeout: 30.0)
                        await connection.disconnect()
                        return (device.id, .success(output))
                    } catch {
                        return (device.id, .failure(error.localizedDescription))
                    }
                }
            }

            for await (id, state) in group {
                results[id] = state
            }
        }
    }
}
