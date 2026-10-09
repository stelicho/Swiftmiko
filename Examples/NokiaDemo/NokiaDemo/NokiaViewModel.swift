// Examples/NokiaDemo/NokiaViewModel.swift
import Foundation
import Swiftmiko
import Combine

/// Demonstrates Nokia SR OS's split personality
/// (Sources/Nokia/NokiaSros.swift): the same driver talks to two
/// genuinely different CLI dialects depending on how the device is
/// provisioned —
///
///   Classical CLI    no config-mode concept at all; enable step uses
///                     "enable-admin".
///   Model-driven CLI  real exclusive-edit config mode with
///                     candidate/commit/discard semantics; enable step
///                     uses plain "enable". Prompt always contains "@".
///
/// Nearly every method in the driver branches at runtime on whether
/// `basePrompt` contains "@" — this view model surfaces that detection
/// directly so the dialect in use is visible rather than invisible
/// plumbing.
@MainActor
final class NokiaViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""
    @Published var adminSecret = ""

    @Published var selectedCommand: NokiaCommand = NokiaCommand.library[0]
    @Published var customCommand = ""
    @Published var useCustomCommand = false

    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    @Published var configText = "configure system name \"swiftmiko-demo\""

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    private var connection: NokiaSros?

    var isConnected: Bool { connection != nil }

    var effectiveCommand: String {
        useCustomCommand ? customCommand : selectedCommand.command
    }

    /// Every branch in NokiaSros keys off whether `basePrompt` contains
    /// "@" — this mirrors that exact check rather than adding a new
    /// one, so what's shown here is guaranteed to match what the
    /// driver itself is doing.
    var dialectDescription: String? {
        guard let connection else { return nil }
        return connection.basePrompt.contains("@")
            ? "Model-driven CLI (config/commit available)"
            : "Classical CLI (no config mode)"
    }

    var isModelDriven: Bool {
        connection?.basePrompt.contains("@") ?? false
    }

    func connect() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "nokia_sros",
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            let newConnection = try await SSHDispatcher.connectHandler(profile: profile) as! NokiaSros

            if !adminSecret.isEmpty {
                try await newConnection.enterEnableMode(secret: adminSecret)
            }
            connection = newConnection
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
            output = try await connection.sendCommand(effectiveCommand, readTimeout: 30.0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Only does anything real on model-driven CLI — on classical CLI
    /// this is a silent no-op inside `enterConfigMode`/`sendConfigSet`
    /// themselves, which this demo deliberately doesn't paper over.
    func loadConfig() async {
        guard let connection else {
            errorMessage = "Not connected — press Connect first."
            return
        }
        guard isModelDriven else {
            errorMessage = "Classical CLI has no config mode — nothing to load."
            return
        }
        let commands = configText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !commands.isEmpty else { return }

        errorMessage = nil
        isRunning = true
        output = ""
        defer { isRunning = false }

        do {
            // Model-driven CLI always stays in config mode after this
            // regardless of the exitConfigMode argument — see
            // NokiaSros.sendConfigSet's override.
            output = try await connection.sendConfigSet(commands)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Activates the private candidate configuration — a no-op if
    /// there's nothing uncommitted, per the driver's own "*(ex)["
    /// marker check.
    func commit() async {
        guard let connection else { return }
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            output = try await connection.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Exits edit-config context, discarding uncommitted changes along
    /// the way if any are present (the driver logs a warning and
    /// issues "discard" itself before actually leaving edit mode).
    func discardAndExitConfig() async {
        guard let connection else { return }
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            output = try await connection.exitConfigMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persists the already-committed configuration to cflash
    /// ("/admin save") — a separate step from commit, same two-phase
    /// shape as Cisco's sendConfigSet + saveConfig.
    func saveConfig() async {
        guard let connection else { return }
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            output = try await connection.saveConfig()
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
