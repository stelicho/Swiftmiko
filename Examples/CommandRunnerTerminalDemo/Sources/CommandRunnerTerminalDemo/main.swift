// Examples/CommandRunnerTerminalDemo/Sources/CommandRunnerTerminalDemo/main.swift
//
// The terminal sibling of CommandRunnerDemo (SwiftUI) and
// CommandRunnerWebDemo (Vapor): connect to a device over SSH, run
// commands, see the output — from a plain terminal, nothing else.
// Builds and runs anywhere Swiftmiko's core library does, which as of
// this demo includes Linux and Windows, not just macOS.
//
// Usage: swift run (from this directory), then follow the prompts.

import Foundation
import Swiftmiko

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

// MARK: - Terminal input helpers

func prompt(_ label: String) -> String {
    print(label, terminator: "")
    return (readLine() ?? "").trimmingCharacters(in: .whitespaces)
}

/// Read a line without echoing it — same technique as
/// Sources/CLITools/CommonOptions.swift's promptSecure(), duplicated
/// here rather than imported since that function is internal to the
/// SwiftmikoCLI module and this demo intentionally depends on nothing
/// but Foundation and the core Swiftmiko library.
func promptSecure(_ label: String) -> String {
    print(label, terminator: "")
#if os(Windows)
    let handle = GetStdHandle(STD_INPUT_HANDLE)
    var oldMode: DWORD = 0
    GetConsoleMode(handle, &oldMode)
    SetConsoleMode(handle, oldMode & ~DWORD(ENABLE_ECHO_INPUT))
    defer {
        SetConsoleMode(handle, oldMode)
        print()
    }
#else
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    // tcflag_t is UInt on Darwin but UInt32 on Linux glibc — cast
    // through it (not a hardcoded UInt) so this builds on both.
    newTermios.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
    defer {
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        print()
    }
#endif
    return readLine() ?? ""
}

// MARK: - Gather connection details

print("Swiftmiko CommandRunner — terminal edition")
print("(macOS, Linux, or Windows — no SwiftUI, no web server)\n")

let host = prompt("Host: ")
guard !host.isEmpty else {
    print("Host is required.")
    exit(1)
}

let deviceTypeInput = prompt("Device type [cisco_ios]: ")
let deviceType = deviceTypeInput.isEmpty ? "cisco_ios" : deviceTypeInput

let username = prompt("Username: ")
let password = promptSecure("Password: ")
let secretInput = promptSecure("Enable secret (optional, Enter to skip): ")
let secret = secretInput.isEmpty ? nil : secretInput

let allowLegacyInput = prompt("Allow legacy AES-CBC ciphers? Only for old gear you control [y/N]: ")
let allowLegacyCiphers = ["y", "yes"].contains(allowLegacyInput.lowercased())

// MARK: - Connect and run an interactive command loop

let profile = ConnectionProfile(
    host: host,
    deviceType: deviceType,
    username: username,
    auth: .password(password),
    secret: secret,
    allowLegacyCiphers: allowLegacyCiphers
)

print("\nConnecting to \(host)...")

do {
    let connection = try await SSHDispatcher.connectHandler(profile: profile)
    print("Connected.")

    if let secret, !secret.isEmpty {
        do {
            try await connection.enterEnableMode(secret: secret)
            print("Entered enable mode.")
        } catch {
            // Not fatal — some device_types (Juniper, Fortinet, VyOS/
            // EdgeRouter, ...) have no enable-mode concept at all, and
            // this demo doesn't know ahead of time which ones do.
            print("Could not enter enable mode (\(error.localizedDescription)) — continuing without it.")
        }
    }

    print("\nType a command to run it, or 'exit'/'quit' to disconnect.\n")

    commandLoop: while true {
        let command = prompt("\(host)> ")
        if command.isEmpty { continue }
        switch command.lowercased() {
        case "exit", "quit":
            break commandLoop
        default:
            do {
                let output = try await connection.sendCommand(command, readTimeout: 30.0)
                print(output)
            } catch {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    await connection.disconnect()
    print("Disconnected.")
} catch {
    print("Connection failed: \(error.localizedDescription)")
    exit(1)
}
