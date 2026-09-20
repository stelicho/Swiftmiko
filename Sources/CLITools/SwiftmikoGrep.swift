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
// Sources/SwiftmikoCLI/SwiftmikoGrep.swift
//
// Port of netmiko_grep.py.

import ArgumentParser
import Foundation

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct SwiftmikoGrep: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiftmiko-grep",
        abstract: "Grep pattern search on Swiftmiko output (defaults to 'show run')"
    )

    @OptionGroup var common: CommonOptions

    @Argument(help: "Pattern to search for")
    var pattern: String?

    @OptionGroup var devicesArg: DevicesArgument

    public init() {}

    public mutating func run() async throws {
        let startTime = Date()

        if common.version {
            print("swiftmiko-grep v\(swiftmikoVersion)")
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
        guard let pattern else {
            throw CLIToolError.grepPatternNotSpecified
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
            format: common.json && common.raw ? "json_raw" : common.json ? "json" : common.raw ? "raw" : "text_highlighted",
            results: valid,
            pattern: pattern,
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

extension SwiftmikoGrep {
    /// See the equivalent extension on `SwiftmikoShow` for why this
    /// disambiguation is necessary.
    public static func runAsMain() async {
        await (self as AsyncParsableCommand.Type).main()
    }
}
