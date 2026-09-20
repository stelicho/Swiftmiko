//
//  ┌───────────────────────────────────────────────────────┐
//  │                   S W I F T M I K O                   │
//  │  Swift-Native Multi-Vendor Network Device Automation  │
//  └───────────────────────────────────────────────────────┘
//
//  Author & Maintainer: K.K. Campbell
//  Created with the assistance of Claude Sonnet 5 (Anthropic),
//  via Claude Code.
//
// Sources/SwiftmikoCLI/SSHConn.swift
//
// Port of helpers.py's ssh_conn() plus the ThreadPoolExecutor
// concurrency used by netmiko_show.py/netmiko_cfg.py/netmiko_grep.py.

import Foundation
import Swiftmiko

let errorPattern = "%%%SWIFTMIKO-ERROR%%%"
let maxWorkers = 25

struct DeviceTask {
    let deviceName: String
    let profile: ConnectionProfile
    let cliCommand: String?
    let cfgCommands: [String]?
}

func sshConn(_ task: DeviceTask) async -> (name: String, output: String) {
    do {
        let connection = try await SSHDispatcher.connectHandler(profile: task.profile)
        defer { Task { await connection.disconnect() } }

        try await connection.enterEnableMode(secret: task.profile.secret ?? "")

        var output = ""
        if let cliCommand = task.cliCommand {
            output += try await connection.sendCommand(cliCommand)
        }
        if let cfgCommands = task.cfgCommands {
            output += try await connection.sendConfigSet(cfgCommands)
        }
        return (task.deviceName, output)
    } catch {
        return (task.deviceName, errorPattern)
    }
}

func runDeviceTasks(_ tasks: [DeviceTask], maxConcurrent: Int) async -> [String: String] {
    var results: [String: String] = [:]
    await withTaskGroup(of: (String, String).self) { group in
        var iterator = tasks.makeIterator()
        func addNext() {
            guard let task = iterator.next() else { return }
            group.addTask { await sshConn(task) }
        }
        for _ in 0..<maxConcurrent { addNext() }
        while let (name, output) = await group.next() {
            results[name] = output
            addNext()
        }
    }
    return results
}

func partitionResults(_ results: [String: String]) -> (valid: [String: String], failed: [String]) {
    var valid: [String: String] = [:]
    var failed: [String] = []
    for (name, output) in results {
        if output == errorPattern { failed.append(name) } else { valid[name] = output }
    }
    return (valid, failed)
}
