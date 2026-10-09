// Examples/PaloAltoDemo/PaloAltoViewModel.swift
import Foundation
import Swiftmiko
import Combine

/// Demonstrates PAN-OS's `commit()` (Sources/Paloalto/PaloAltoPanos.swift)
/// — the most elaborate commit command-string construction in this
/// entire vendor set: a plain commit is just "commit", but a partial
/// commit can be scoped to device-and-network config, policy-and-objects
/// config, a specific vsys, or "no-vsys" (everything except vsys-scoped
/// config) — any combination of which is only valid when `partial` is
/// set, exactly like the guard this view model mirrors below.
///
/// IMPORTANT caveat, surfaced here rather than left for Connect to fail
/// on silently: PAN-OS's SSH login typically uses keyboard-interactive
/// authentication (RFC 4256) rather than plain password auth, because
/// older/certain PAN-OS versions fold a EULA-acceptance prompt into the
/// same exchange as the password prompt. The driver defines
/// `PaloAltoInteractiveAuthHandler` for exactly this, but nothing in
/// the NIOSSH transport layer actually wires it in yet — `connect()`
/// here goes through plain password auth. Devices that accept password
/// auth as a fallback will connect fine; devices that require
/// keyboard-interactive will fail at the transport level before this
/// driver even gets a chance to run. Worth knowing before assuming a
/// failed connection here is this demo's bug rather than a real gap.
@MainActor
final class PaloAltoViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""

    @Published var selectedCommand: PaloAltoCommand = PaloAltoCommand.library[0]
    @Published var customCommand = ""
    @Published var useCustomCommand = false

    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    // MARK: Config / Commit workflow

    @Published var configText = "set deviceconfig system hostname swiftmiko-demo"
    @Published var inConfigMode = false

    @Published var commitComment = ""
    @Published var commitForce = false
    @Published var commitPartial = false
    @Published var commitDeviceAndNetwork = false
    @Published var commitPolicyAndObjects = false
    @Published var commitVsys = ""
    @Published var commitNoVsys = false

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    private var connection: PaloAltoPanosBase?

    var isConnected: Bool { connection != nil }

    var effectiveCommand: String {
        useCustomCommand ? customCommand : selectedCommand.command
    }

    /// Mirrors `commit()`'s own guard: the scoping flags only mean
    /// anything when `partial` is set, so this disables the Commit
    /// button instead of always round-tripping to the device just to
    /// be refused with `SwiftmikoError.invalidArgument`.
    var commitArgumentsValid: Bool {
        commitPartial || !(commitDeviceAndNetwork || commitPolicyAndObjects || !commitVsys.isEmpty || commitNoVsys)
    }

    func connect() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "paloalto_panos",
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            connection = try await SSHDispatcher.connectHandler(profile: profile) as! PaloAltoPanosBase
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

    /// Loads `configText` into the candidate configuration and stays
    /// in config mode, so the Commit section below has something
    /// uncommitted to act on.
    func loadConfig() async {
        guard let connection else {
            errorMessage = "Not connected — press Connect first."
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
            output = try await connection.sendConfigSet(commands, exitConfigMode: false)
            inConfigMode = try await connection.isInConfigMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exitConfig() async {
        guard let connection else { return }
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            output = try await connection.exitConfigMode()
            inConfigMode = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commit() async {
        guard let connection else {
            errorMessage = "Not connected — press Connect first."
            return
        }
        guard commitArgumentsValid else {
            errorMessage = "Invalid commit argument combination — scoping flags require \"Partial\"."
            return
        }

        errorMessage = nil
        isRunning = true
        output = ""
        defer { isRunning = false }

        do {
            output = try await connection.commit(
                comment: commitComment,
                force: commitForce,
                partial: commitPartial,
                deviceAndNetwork: commitDeviceAndNetwork,
                policyAndObjects: commitPolicyAndObjects,
                vsys: commitVsys,
                noVsys: commitNoVsys
            )
            inConfigMode = try await connection.isInConfigMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        await connection?.disconnect()
        connection = nil
        output = ""
        inConfigMode = false
    }
}
