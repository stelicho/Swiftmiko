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
// Sources/SwiftmikoCLI/SwiftmikoShow.swift
//
// Port of netmiko_show.py.

import ArgumentParser
import Foundation

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct SwiftmikoShow: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiftmiko-show",
        abstract: "Execute show command using Swiftmiko (defaults to 'show run')"
    )

    @OptionGroup var common: CommonOptions
    @OptionGroup var devicesArg: DevicesArgument

    public init() {}

    public mutating func run() async throws {
        let startTime = Date()

        if common.version {
            print("swiftmiko-show v\(swiftmikoVersion)")
            return
        }
        if common.listDevices {
            let config = try loadSwiftmikoYAML()
            displayInventory(config)
            return
        }

        guard let deviceOrGroup = devicesArg.devices?.trimmingCharacters(in: .whitespaces),
              !deviceOrGroup.isEmpty else {
            throw CLIToolError.devicesNotSpecified
        }

        let cliVars = common.extractCLIVariables()
        let devices = try obtainDevices(deviceOrGroup)

        var tasks: [DeviceTask] = []
        for (name, params) in devices {
            let updated = updateDeviceParams(
                params,
                username: cliVars.username,
                password: cliVars.password,
                secret: cliVars.secret
            )
            let profile = try connectionProfile(from: updated)
            let command = common.cmd ?? showRunMapper[profile.deviceType] ?? "show run"
            tasks.append(DeviceTask(
                deviceName: name,
                profile: profile,
                cliCommand: command,
                cfgCommands: nil
            ))
        }

        let results = await runDeviceTasks(tasks, maxConcurrent: maxWorkers)
        let (valid, failed) = partitionResults(results)

        try outputDispatcher(
            format: common.json && common.raw ? "json_raw" : common.json ? "json" : common.raw ? "raw" : "text",
            results: valid,
            hideEmpty: common.hideEmpty
        )

        if common.displayRuntime {
            print("Total time: \(Date().timeIntervalSince(startTime))")
        }
        if !common.hideFailed {
            outputFailedDevices(failed)
        }
    }
}

extension SwiftmikoShow {
    /// `Type.main()` is ambiguous between `ParsableCommand`'s sync
    /// overload and `AsyncParsableCommand`'s async one — Swift prefers
    /// the sync candidate even when called with `await` (SE-0296), which
    /// skips `run()`'s async path entirely. Typing the reference as
    /// `AsyncParsableCommand.Type` removes the sync overload from
    /// consideration so entrypoints don't need to know about this.
    public static func runAsMain() async {
        await (self as AsyncParsableCommand.Type).main()
    }
}

/// Maps to netmiko.utilities.SHOW_RUN_MAPPER — a per-device-type
/// default show command. Netmiko's actual table wasn't part of the
/// files reviewed here; this is a minimal placeholder covering common
/// cases and should be filled out from the real utilities.py source.
let showRunMapper: [String: String] = [
    "cisco_ios": "show run",
    "cisco_nxos": "show run",
    "cisco_xr": "show run",
    "arista_eos": "show run",
    "juniper_junos": "show configuration",
]

let swiftmikoVersion = "0.1.0"
