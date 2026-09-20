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
// Sources/SwiftmikoCLI/CommonOptions.swift
//
// Port of netmiko/cli_tools/argument_handling.py's common_args() and
// the shared parsing/validation logic in parse_arguments().

import ArgumentParser
import Foundation

/// Arguments shared by every Swiftmiko CLI tool.
///
/// Maps to argument_handling.py's common_args(parser). Modeled as a
/// ParsableArguments struct rather than a shared subcommand parent,
/// since Netmiko's tools are five independent binaries, not
/// subcommands of one program.
struct CommonOptions: ParsableArguments {
    @Option(name: .customLong("cmd"), help: "Command to execute")
    var cmd: String?

    @Option(help: "Username")
    var username: String?

    /// Maps to Python's `--password` (store_true) → getpass() prompt
    /// at runtime. The boolean flag here signals "prompt interactively",
    /// matching Netmiko's own two-step design (flag now, prompt later)
    /// rather than accepting the password directly on the command
    /// line, which would leak it into shell history.
    @Flag(help: "Prompt for password")
    var password: Bool = false

    @Flag(help: "Prompt for enable secret")
    var secret: Bool = false

    @Flag(name: .customLong("list-devices"), help: "List devices from inventory")
    var listDevices: Bool = false

    @Flag(name: .customLong("display-runtime"), help: "Display program runtime")
    var displayRuntime: Bool = false

    @Flag(name: .customLong("hide-failed"), help: "Hide failed devices")
    var hideFailed: Bool = false

    @Flag(name: .customLong("hide-empty"), help: "Hide empty responses")
    var hideEmpty: Bool = false

    @Flag(help: "Output results in JSON format")
    var json: Bool = false

    @Flag(help: "Display raw output")
    var raw: Bool = false

    @Flag(help: "Display version")
    var version: Bool = false
}

/// The device/group positional argument shared by show, cfg, and grep.
/// Maps to show_args()/cfg_args()'s `devices` positional.
struct DevicesArgument: ParsableArguments {
    @Argument(help: "Device or group to connect to")
    var devices: String?
}

/// Extracted, ready-to-use values derived from CommonOptions after
/// interactive prompting.
///
/// Maps to extract_cli_vars() — Python returns a loose dict;
/// Swift gets a proper struct.
struct CLIVariables {
    let username: String?
    let password: String?
    let secret: String?
}

enum CLIToolError: Error, CustomStringConvertible {
    case devicesNotSpecified
    case noConfigurationCommandsProvided
    case grepPatternNotSpecified
    case deviceOrGroupNotFound(String)
    case encryptionKeyNotProvided
    case encryptionTypeNotProvided

    var description: String {
        switch self {
        case .devicesNotSpecified:
            return "Devices not specified."
        case .noConfigurationCommandsProvided:
            return "No configuration commands provided."
        case .grepPatternNotSpecified:
            return "Grep pattern not specified."
        case .deviceOrGroupNotFound(let name):
            return "Error reading from swiftmiko devices file. Device or group not found: \(name)"
        case .encryptionKeyNotProvided:
            return "Encryption key not provided.\nUse --key or set SWIFTMIKO_TOOLS_KEY environment variable."
        case .encryptionTypeNotProvided:
            return "Encryption type not provided.\nUse --type or set 'encryption_type' in .swiftmiko.yml in the '__meta__' section."
        }
    }
}

extension CommonOptions {
    /// Prompt for password/secret interactively if the corresponding
    /// flag was set, matching Netmiko's getpass() calls.
    ///
    /// Maps to extract_cli_vars()'s cli_username/cli_password/cli_secret
    /// extraction. The version/list-devices short-circuit branches
    /// (sys.exit(0) in Python) are handled by the caller checking
    /// `version`/`listDevices` before calling this, since Swift
    /// doesn't have a direct sys.exit-from-a-library-function idiom
    /// that's appropriate to bury in a helper.
    func extractCLIVariables() -> CLIVariables {
        CLIVariables(
            username: username,
            password: password ? promptSecure("Password: ") : nil,
            secret: secret ? promptSecure("Enable secret: ") : nil
        )
    }
}

/// Read a line from stdin without echoing it — the Swift equivalent
/// of Python's getpass().
///
/// Foundation has no built-in getpass equivalent; this uses termios
/// directly via Glibc/Darwin to disable echo for the duration of the
/// read, then restores the terminal's original settings.
func promptSecure(_ prompt: String) -> String {
    print(prompt, terminator: "")
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
    defer {
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        print()
    }
    return readLine() ?? ""
}
