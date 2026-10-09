// Examples/MikrotikDemo/MikrotikViewModel.swift
import Foundation
import Swiftmiko
import Combine

/// Demonstrates MikroTik RouterOS/SwitchOS
/// (Sources/Mikrotik/Mikrotik.swift) — the most idiosyncratic driver in
/// this vendor set, though almost none of that idiosyncrasy is visible
/// at this API level, which is the point:
///
///   - Terminal width/color/mode flags ride along on the SSH username
///     itself (e.g. "admin+ct511w4098h"), not a post-connect command.
///   - Login can present a license prompt, an unlicensed banner, a
///     default-configuration removal notice, or a forced new-password
///     prompt, in any combination — all absorbed automatically before
///     `connect()` even returns.
///   - Output cleanup accounts for the device repainting the prompt
///     line, which otherwise shows up as literal duplicate text.
///
/// This driver also conforms to `NoEnable`/`NoConfig` — RouterOS has no
/// privilege escalation and no separate config mode via this
/// connection type, so unlike the other examples there's intentionally
/// no enable-secret field or config/commit workflow here.
@MainActor
final class MikrotikViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""

    @Published var selectedCommand: MikrotikCommand = MikrotikCommand.library[0]
    @Published var customCommand = ""
    @Published var useCustomCommand = false

    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    private var connection: MikrotikBase?

    var isConnected: Bool { connection != nil }

    var effectiveCommand: String {
        useCustomCommand ? customCommand : selectedCommand.command
    }

    func connect() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "mikrotik_routeros",
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            // By the time this returns, connectHandler's session
            // preparation has already: appended the terminal-config
            // suffix to the username before opening the transport,
            // walked whatever combination of post-login prompts
            // RouterOS presented, and detected the base prompt.
            connection = try await SSHDispatcher.connectHandler(profile: profile) as! MikrotikBase
        } catch {
            errorMessage = error.localizedDescription
            connection = nil
        }
    }

    func runCommand() async {
        guard let connection else {
            errorMessage = "Not connected — press Connect first."
            return
        }
        guard !effectiveCommand.isEmpty else { return }

        errorMessage = nil
        isRunning = true
        output = ""
        defer { isRunning = false }

        do {
            output = try await connection.sendCommand(effectiveCommand, readTimeout: 20.0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await connection?.disconnect()
        connection = nil
        output = ""
    }
}
