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
// Sources/SwiftmikoCLI/SwiftmikoCfg.swift
//
// Port of netmiko_cfg.py.

import ArgumentParser
import Foundation

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public struct SwiftmikoCfg: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "swiftmiko-cfg",
        abstract: "Execute configuration command using Swiftmiko"
    )

    @OptionGroup var common: CommonOptions
    @OptionGroup var devicesArg: DevicesArgument

    @Option(help: "Read commands from file")
    var infile: String?

    public init() {}

    public mutating func run() async throws {
        let startTime = Date()

        if common.version {
            print("swiftmiko-cfg v\(swiftmikoVersion)")
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

        // Maps to the CFG COMMAND HANDLER block: a literal "\n" in
        // the --cmd string splits into multiple commands; otherwise
        // fall back to --infile.
        let cfgCommands: [String]
        if let cmd = common.cmd {
            if cmd.contains("\\n") {
                cfgCommands = cmd.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: "\\n")
            } else {
                cfgCommands = [cmd]
            }
        } else if let infile {
            let contents = try String(contentsOfFile: infile, encoding: .utf8)
            cfgCommands = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
        } else {
            throw CLIToolError.noConfigurationCommandsProvided
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
            tasks.append(DeviceTask(
                deviceName: name,
                profile: profile,
                cliCommand: nil,
                cfgCommands: cfgCommands
            ))
        }

        let results = await runDeviceTasks(tasks, maxConcurrent: maxWorkers)
        let (valid, failed) = partitionResults(results)

        try outputDispatcher(
            format: common.json && common.raw ? "json_raw" : common.json ? "json" : common.raw ? "raw" : "text",
            results: valid
        )

        if common.displayRuntime {
            print("Total time: \(Date().timeIntervalSince(startTime))")
        }
        if !common.hideFailed {
            outputFailedDevices(failed)
        }
    }
}

extension SwiftmikoCfg {
    /// See the equivalent extension on `SwiftmikoShow` for why this
    /// disambiguation is necessary.
    public static func runAsMain() async {
        await (self as AsyncParsableCommand.Type).main()
    }
}
