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
//
//  Utilities.swift
//  Swiftmiko
//
//  Port of netmiko/utilities.py
//

import Foundation

public enum SwiftmikoUtilityError: Error {
    case fileNotFound(String)
    case invalidValue(String)
    case parserUnavailable(String)
    case parsingFailed(String)
}

/// Commands used by `send_command("show run")` for platforms with a
/// different running-configuration command.
public let showRunMapper: [String: String] = {
    let base: [String: String] = [
        "brocade_fos": "configShow",
        "juniper": "show configuration",
        "juniper_junos": "show configuration",
        "extreme": "show configuration",
        "extreme_ers": "show running-config",
        "extreme_exos": "show configuration",
        "extreme_netiron": "show running-config",
        "extreme_nos": "show running-config",
        "extreme_slx": "show running-config",
        "extreme_vdx": "show running-config",
        "extreme_vsp": "show running-config",
        "extreme_wing": "show running-config",
        "ericsson_ipos": "show configuration",
        "hp_comware": "display current-configuration",
        "huawei": "display current-configuration",
        "fortinet": "show full-configuration",
        "checkpoint": "show configuration",
        "cisco_wlc": "show run-config",
        "enterasys": "show running-config",
        "dell_force10": "show running-config",
        "avaya_vsp": "show running-config",
        "avaya_ers": "show running-config",
        "brocade_vdx": "show running-config",
        "brocade_nos": "show running-config",
        "brocade_fastiron": "show running-config",
        "brocade_netiron": "show running-config",
        "alcatel_aos": "show configuration snapshot",
        "cros_mtbr": "show running-config"
    ]

    var expanded = base
    for (platform, command) in base {
        expanded["\(platform)_ssh"] = command
    }
    return expanded
}()

public let swiftmikoBaseDirectory = "~/.swiftmiko"

// MARK: - Configuration files

/// Adapter for a YAML package selected by the application.
public protocol YAMLDecoderAdapter {
    func decode(data: Data) throws -> Any
}

public func loadYAMLFile(
    _ yamlFile: String,
    using decoder: YAMLDecoderAdapter
) throws -> Any {
    guard FileManager.default.fileExists(atPath: yamlFile) else {
        throw SwiftmikoUtilityError.fileNotFound(yamlFile)
    }
    do {
        return try decoder.decode(
            data: Data(contentsOf: URL(fileURLWithPath: yamlFile))
        )
    } catch {
        throw SwiftmikoUtilityError.parsingFailed(
            "Unable to parse YAML file \(yamlFile): \(error)"
        )
    }
}

/// The default overload is intentionally explicit about the optional
/// dependency. Swift Foundation does not include a YAML parser.
public func loadYAMLFile(_ yamlFile: String) throws -> Any {
    throw SwiftmikoUtilityError.parserUnavailable(
        "YAML support requires a YAMLDecoderAdapter"
    )
}

public func findConfigFile(_ fileName: String? = nil) throws -> String {
    if let fileName, FileManager.default.fileExists(atPath: fileName) {
        return fileName
    }

    let environmentPath = ProcessInfo.processInfo.environment[
        "SWIFTMIKO_TOOLS_CFG"
    ] ?? ""
    if !environmentPath.isEmpty &&
        FileManager.default.fileExists(atPath: environmentPath) {
        return environmentPath
    }

    let home = NSHomeDirectory()
    let searchPaths = [".", home]
    for directory in searchPaths {
        for name in [".swiftmiko.yml", "swiftmiko.yml"] {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
    }

    throw SwiftmikoUtilityError.fileNotFound(
        ".swiftmiko.yml was not found in SWIFTMIKO_TOOLS_CFG, the current directory, or the home directory"
    )
}

/// Compatibility spelling matching Netmiko's helper name.
public func findCfgFile(_ fileName: String? = nil) throws -> String {
    try findConfigFile(fileName)
}

public func loadSwiftmikoYML(
    _ fileName: String? = nil,
    using decoder: YAMLDecoderAdapter
) throws -> (configuration: Any, devices: Any) {
    let file = try findConfigFile(fileName)
    guard var document = try loadYAMLFile(file, using: decoder)
        as? [String: Any] else {
        throw SwiftmikoUtilityError.parsingFailed(
            "Swiftmiko YAML root must be a mapping"
        )
    }
    let configuration = document.removeValue(forKey: "__meta__") ?? [:]
    return (configuration, document)
}

public func loadDevices(
    _ fileName: String? = nil,
    using decoder: YAMLDecoderAdapter
) throws -> Any {
    try loadYAMLFile(try findConfigFile(fileName), using: decoder)
}

public func displayInventory(
    _ devices: [String: Any]
) {
    var groups = ["all"]
    var inventory: [(String, String)] = []

    for (name, value) in devices {
        if value is [Any] {
            groups.append(name)
        } else if let device = value as? [String: Any],
                  let type = device["device_type"] as? String {
            inventory.append((name, type))
        }
    }

    groups.sort()
    inventory.sort { $0.0 < $1.0 }

    print("\nDevices:")
    print(String(repeating: "-", count: 40))
    for (name, type) in inventory {
        print("\(name.padding(toLength: 25, withPad: " ", startingAt: 0))\(type)")
    }
    print("\nGroups:")
    print(String(repeating: "-", count: 40))
    groups.forEach { print($0) }
    print()
}

public func obtainAllDevices(
    from devices: [String: Any]
) -> [String: Any] {
    devices.filter { !($0.value is [Any]) }
}

public func findSwiftmikoDirectory() throws -> (
    baseDirectory: String,
    temporaryDirectory: String
) {
    let environment = ProcessInfo.processInfo.environment["SWIFTMIKO_DIR"]
    let base = NSString(
        string: environment ?? swiftmikoBaseDirectory
    ).expandingTildeInPath

    guard base != "/" else {
        throw SwiftmikoUtilityError.invalidValue(
            "/ cannot be the Swiftmiko base directory"
        )
    }
    return (base, "\(base)/tmp")
}

public func obtainSwiftmikoFilename(_ deviceName: String) throws -> String {
    let directories = try findSwiftmikoDirectory()
    return "\(directories.temporaryDirectory)/\(deviceName).txt"
}

public func findSwiftmikoDir() throws -> (
    baseDirectory: String,
    temporaryDirectory: String
) {
    try findSwiftmikoDirectory()
}

@discardableResult
public func writeTemporaryFile(
    deviceName: String,
    output: String
) throws -> String {
    let fileName = try obtainSwiftmikoFilename(deviceName)
    try ensureDirectoryExists(
        URL(fileURLWithPath: fileName).deletingLastPathComponent().path
    )
    try output.write(
        to: URL(fileURLWithPath: fileName),
        atomically: true,
        encoding: .utf8
    )
    return fileName
}

@discardableResult
public func writeTmpFile(
    deviceName: String,
    output: String
) throws -> String {
    try writeTemporaryFile(deviceName: deviceName, output: output)
}

public func ensureDirectoryExists(_ directory: String) throws {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(
        atPath: directory,
        isDirectory: &isDirectory
    ) {
        guard isDirectory.boolValue else {
            throw SwiftmikoUtilityError.invalidValue(
                "\(directory) is not a directory"
            )
        }
        return
    }
    try FileManager.default.createDirectory(
        atPath: directory,
        withIntermediateDirectories: true
    )
}

public func ensureDirExists(_ directory: String) throws {
    try ensureDirectoryExists(directory)
}

public func writeBytes(
    _ output: Any,
    encoding: String.Encoding = .utf8
) throws -> Data {
    if let data = output as? Data {
        return data
    }
    if let string = output as? String {
        guard let data = string.data(using: encoding) else {
            throw SwiftmikoUtilityError.invalidValue(
                "Unable to encode output"
            )
        }
        return data
    }
    throw SwiftmikoUtilityError.invalidValue(
        "Output must be a String or Data"
    )
}

// MARK: - Serial ports and templates

public protocol SerialPortProvider {
    func availablePortNames() throws -> [String]
}

public func checkSerialPort(
    _ name: String,
    using provider: SerialPortProvider
) throws -> String {
    let matches = try provider.availablePortNames().filter { $0 == name }
    if matches.count > 1 {
        throw SwiftmikoUtilityError.invalidValue(
            "Multiple ports found matching \(name)"
        )
    }
    guard let match = matches.first else {
        let available = try provider.availablePortNames().joined(separator: ",")
        throw SwiftmikoUtilityError.invalidValue(
            "Device \(name) not found. Available devices are: \(available)"
        )
    }
    return match
}

public func getTemplateDirectory(
    skipPackage: Bool = false
) throws -> String {
    let environment = ProcessInfo.processInfo.environment["NET_TEXTFSM"]
    if let environment, !environment.isEmpty {
        let expanded = NSString(string: environment).expandingTildeInPath
        let index = URL(fileURLWithPath: expanded)
            .appendingPathComponent("index").path
        let templates = FileManager.default.fileExists(atPath: index)
            ? expanded
            : "\(expanded)/templates"
        if FileManager.default.fileExists(atPath: "\(templates)/index") {
            return URL(fileURLWithPath: templates).standardized.path
        }
    }

    if !skipPackage {
        // Swift packages can expose their bundled template directory through
        // Bundle.module; the executable chooses that bundle-specific adapter.
        // We intentionally do not guess a package location here.
    }

    let fallback = "\(NSHomeDirectory())/ntc-templates/ntc_templates/templates"
    guard FileManager.default.fileExists(atPath: "\(fallback)/index") else {
        throw SwiftmikoUtilityError.invalidValue(
            "Directory containing the TextFSM index file was not found. Set NET_TEXTFSM."
        )
    }
    return fallback
}

public func getTemplateDir(skipPackage: Bool = false) throws -> String {
    try getTemplateDirectory(skipPackage: skipPackage)
}

// MARK: - Structured-data parser adapters

public protocol TextFSMParserAdapter {
    func parse(
        rawOutput: String,
        platform: String?,
        command: String?,
        template: String?
    ) throws -> [[String: String]]
}

public protocol TTPParserAdapter {
    func parse(rawOutput: String, template: String) throws -> [[String: Any]]
}

/// Adapter for TTP templates that collect additional command output from a
/// live connection. This replaces Python's dynamic `getattr(connection, ...)`
/// calls with an explicit command collector.
public protocol TTPTemplateExecutionAdapter {
    func execute(
        template: String,
        connection: BaseConnection,
        resultOptions: [String: Any],
        options: [String: Any]
    ) async throws -> Any
}

public protocol GenieParserAdapter {
    func parse(
        rawOutput: String,
        platform: String,
        command: String
    ) throws -> [String: Any]
}

public func clitableToDictionary(
    headers: [String],
    rows: [[String]]
) -> [[String: String]] {
    rows.map { row in
        Dictionary(
            uniqueKeysWithValues: row.enumerated().compactMap { index, value in
                guard index < headers.count else { return nil }
                return (headers[index].lowercased(), value)
            }
        )
    }
}

public func clitableToDict(
    headers: [String],
    rows: [[String]]
) -> [[String: String]] {
    clitableToDictionary(headers: headers, rows: rows)
}

public func getStructuredDataTextFSM(
    rawOutput: String,
    platform: String? = nil,
    command: String? = nil,
    template: String? = nil,
    raiseParsingError: Bool = false,
    parser: TextFSMParserAdapter? = nil
) throws -> Any {
    guard platform != nil && command != nil || template != nil else {
        throw SwiftmikoUtilityError.invalidValue(
            "Either platform/command or template must be specified"
        )
    }
    guard let parser else {
        if raiseParsingError {
            throw SwiftmikoUtilityError.parserUnavailable(
                "TextFSM support requires a TextFSMParserAdapter"
            )
        }
        return rawOutput
    }
    do {
        let result = try parser.parse(
            rawOutput: rawOutput,
            platform: platform,
            command: command,
            template: template
        )
        return result.isEmpty ? rawOutput : result
    } catch {
        if raiseParsingError {
            throw SwiftmikoUtilityError.parsingFailed(
                "Failed to parse CLI output using TextFSM: \(error)"
            )
        }
        return rawOutput
    }
}

public func getStructuredDataTTP(
    rawOutput: String,
    template: String,
    raiseParsingError: Bool = false,
    parser: TTPParserAdapter? = nil
) throws -> Any {
    guard let parser else {
        if raiseParsingError {
            throw SwiftmikoUtilityError.parserUnavailable(
                "TTP support requires a TTPParserAdapter"
            )
        }
        return rawOutput
    }
    do {
        let result = try parser.parse(
            rawOutput: rawOutput,
            template: template
        )
        return result.isEmpty ? rawOutput : result
    } catch {
        if raiseParsingError {
            throw SwiftmikoUtilityError.parsingFailed(
                "Failed to parse CLI output using TTP: \(error)"
            )
        }
        return rawOutput
    }
}

/// Execute a TTP template against a live connection.
public func runTTPTemplate(
    connection: BaseConnection,
    template: String,
    resultOptions: [String: Any],
    options: [String: Any] = [:],
    adapter: TTPTemplateExecutionAdapter
) async throws -> Any {
    try await adapter.execute(
        template: template,
        connection: connection,
        resultOptions: resultOptions,
        options: options
    )
}

public func getStructuredDataGenie(
    rawOutput: String,
    platform: String,
    command: String,
    raiseParsingError: Bool = false,
    parser: GenieParserAdapter? = nil
) throws -> Any {
    guard platform.contains("cisco") || platform.contains("linux") else {
        return rawOutput
    }
    guard let parser else {
        if raiseParsingError {
            throw SwiftmikoUtilityError.parserUnavailable(
                "Genie support requires a GenieParserAdapter"
            )
        }
        return rawOutput
    }
    do {
        return try parser.parse(
            rawOutput: rawOutput,
            platform: platform,
            command: command
        )
    } catch {
        if raiseParsingError {
            throw SwiftmikoUtilityError.parsingFailed(
                "Failed to parse CLI output using Genie: \(error)"
            )
        }
        return rawOutput
    }
}

public func structuredDataConverter(
    rawData: String,
    command: String,
    platform: String,
    useTextFSM: Bool = false,
    useTTP: Bool = false,
    useGenie: Bool = false,
    textFSMTemplate: String? = nil,
    ttpTemplate: String? = nil,
    raiseParsingError: Bool = false,
    textFSMParser: TextFSMParserAdapter? = nil,
    ttpParser: TTPParserAdapter? = nil,
    genieParser: GenieParserAdapter? = nil
) throws -> Any {
    let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

    if useTextFSM {
        let result = try getStructuredDataTextFSM(
            rawOutput: rawData,
            platform: platform,
            command: normalizedCommand,
            template: textFSMTemplate,
            raiseParsingError: raiseParsingError,
            parser: textFSMParser
        )
        if !(result is String) { return result }
    }

    if useTTP {
        guard let ttpTemplate else {
            throw SwiftmikoUtilityError.invalidValue(
                "ttpTemplate must be set when useTTP is true"
            )
        }
        let result = try getStructuredDataTTP(
            rawOutput: rawData,
            template: ttpTemplate,
            raiseParsingError: raiseParsingError,
            parser: ttpParser
        )
        if !(result is String) { return result }
    }

    if useGenie {
        let result = try getStructuredDataGenie(
            rawOutput: rawData,
            platform: platform,
            command: normalizedCommand,
            raiseParsingError: raiseParsingError,
            parser: genieParser
        )
        if !(result is String) { return result }
    }
    return rawData
}

/// Compatibility alias for Netmiko's `get_structured_data`.
public func getStructuredData(
    rawOutput: String,
    platform: String? = nil,
    command: String? = nil,
    template: String? = nil,
    raiseParsingError: Bool = false,
    parser: TextFSMParserAdapter? = nil
) throws -> Any {
    try getStructuredDataTextFSM(
        rawOutput: rawOutput,
        platform: platform,
        command: command,
        template: template,
        raiseParsingError: raiseParsingError,
        parser: parser
    )
}

// MARK: - Timing and text helpers

public func measureExecution<T>(
    _ label: String = "",
    operation: () throws -> T
) rethrows -> T {
    let start = Date()
    defer {
        let elapsed = Date().timeIntervalSince(start)
        print("\(label): Elapsed time: \(elapsed)s")
    }
    return try operation()
}

/// Swift replacement for Netmiko's `select_cmd_verify` decorator.
///
/// Swift does not support decorating an arbitrary method at runtime. Callers
/// can use this small policy helper at the point where command options are
/// assembled.
public func selectCmdVerify(
    commandVerify: Bool?,
    globalCommandVerify: Bool?
) -> Bool? {
    globalCommandVerify ?? commandVerify
}

public func measureAsyncExecution<T>(
    _ label: String = "",
    operation: () async throws -> T
) async rethrows -> T {
    let start = Date()
    defer {
        let elapsed = Date().timeIntervalSince(start)
        print("\(label): Elapsed time: \(elapsed)s")
    }
    return try await operation()
}

public func calcOldTimeout(
    maxLoops: Int? = nil,
    delayFactor: Double? = nil,
    loopDelay: Double = 0.2,
    oldTimeout: Int = 100
) -> Double {
    var loops = maxLoops ?? 500
    let factor = delayFactor ?? 1.0
    if factor == 1.0 && loops == 500 {
        loops = Int(Double(oldTimeout) / loopDelay)
    }
    return Double(loops) * loopDelay * factor
}

public func nokiaContextFilter(
    _ data: String
) -> String {
    let pattern = #"^!?\*?(\((ex|gl|pr|ro)\))?\[.*\]"#
    return data.replacingOccurrences(
        of: pattern,
        with: "",
        options: [.regularExpression]
    )
}
