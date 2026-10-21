// Examples/ScriptDemo/Sources/ScriptDemo/ScriptDemo.swift
//
// Proof that Swiftmiko scripts cleanly, the way Netmiko does: no
// SwiftUI, no Xcode project, no YAML inventory file — just a
// connection-profile dictionary's worth of flags on the command line,
// one command, and output. Builds and runs on macOS, Linux, and
// Windows, anywhere Swiftmiko's core library does.
//
// Usage: swift run (from this directory)
//   --host 192.168.1.1 --username admin --command "show version"
// Add --password to skip the secure prompt, and
// --allow-legacy-ciphers for old IOS images that predate AES-GCM.

import ArgumentParser
import Foundation
@preconcurrency import Swiftmiko

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

struct ScriptDemo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "script-demo",
        abstract: "Connect to a Cisco IOS device and run one command — a minimal, flag-driven Swiftmiko script."
    )

    @Option(help: "Device hostname or IP address.")
    var host: String

    @Option(help: "SSH username.")
    var username: String

    @Option(help: "SSH password. Omit this to be prompted securely instead of passing it on the command line.")
    var password: String?

    @Flag(help: "Opt in to legacy AES-CBC ciphers, for old IOS images that predate AES-GCM. Only for lab/EOL gear you control.")
    var allowLegacyCiphers: Bool = false

    @Option(help: "Command to run on the device.")
    var command: String = "show version"

    init() {}

    mutating func run() async throws {
        let resolvedPassword = password ?? promptSecure("Password: ")

        let profile = ConnectionProfile(
            host: host,
            deviceType: "cisco_ios",
            username: username,
            auth: .password(resolvedPassword),
            allowLegacyCiphers: allowLegacyCiphers
        )

        print("Connecting to \(host)...")
        let connection = try await SSHDispatcher.connectHandler(profile: profile)
        print("Connected. Running: \(command)")

        let output = try await connection.sendCommand(command, readTimeout: 30.0)
        print(output)

        await connection.disconnect()
        print("Disconnected.")
    }
}

/// Read a line without echoing it — same technique as
/// Sources/CLITools/CommonOptions.swift's promptSecure(), duplicated
/// here rather than imported since that function is internal to the
/// SwiftmikoCLI module and this demo intentionally depends on nothing
/// but Foundation, ArgumentParser, and the core Swiftmiko library.
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

extension ScriptDemo {
    /// `Type.main()` is ambiguous between `ParsableCommand`'s sync
    /// overload and `AsyncParsableCommand`'s async one — Swift prefers
    /// the sync candidate even when called with `await` (SE-0296),
    /// which skips `run()`'s async path entirely. Typing the reference
    /// as `AsyncParsableCommand.Type` removes the sync overload from
    /// consideration — same workaround `Sources/CLITools/SwiftmikoShow.swift`
    /// uses, see its comment for the full explanation.
    static func runAsMain() async {
        await (self as AsyncParsableCommand.Type).main()
    }
}
