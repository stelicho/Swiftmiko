// Examples/JuniperDemo/JuniperViewModel.swift
import Foundation
import Swiftmiko
import Combine

/// Demonstrates JunOS's candidate-configuration / commit model —
/// the feature that makes Juniper's driver (Sources/Juniper/Juniper.swift)
/// the richest single-vendor config workflow in this vendor set.
///
/// Unlike Cisco's immediate-apply + "write memory" model, JunOS config
/// changes land in a private candidate configuration first and do
/// nothing to the running system until an explicit commit — which
/// itself has several distinct forms (plain, confirmed-with-auto-rollback,
/// check-only dry run, commented, and-quit) all exposed here.
@MainActor
final class JuniperViewModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var password = ""

    @Published var selectedCommand: JuniperCommand = JuniperCommand.library[0]
    @Published var customCommand = ""
    @Published var useCustomCommand = false

    @Published var output = ""
    @Published var isRunning = false
    @Published var errorMessage: String?

    // MARK: Config / Commit workflow

    @Published var configText = "set system host-name swiftmiko-demo"
    @Published var inConfigMode = false

    @Published var commitCheck = false
    @Published var commitConfirm = false
    @Published var commitConfirmDelay = ""
    @Published var commitComment = ""
    @Published var commitAndQuit = false

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    @Published var allowLegacyCiphers = false

    private var connection: JuniperBase?

    var isConnected: Bool { connection != nil }

    var effectiveCommand: String {
        useCustomCommand ? customCommand : selectedCommand.command
    }

    /// `commit(check:)` rejects being combined with confirm/comment,
    /// and a confirm delay without `confirm` is meaningless — mirrored
    /// here so the Commit button simply stays disabled instead of
    /// always round-tripping to the device just to be refused.
    var commitArgumentsValid: Bool {
        if commitCheck && (commitConfirm || !commitComment.isEmpty) { return false }
        if !commitConfirm && !commitConfirmDelay.isEmpty { return false }
        return true
    }

    func connect() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "juniper_junos",
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            // connectHandler's session preparation already detects
            // whether the session landed at the raw FreeBSD shell
            // instead of the JunOS CLI and switches into CLI mode for
            // us — nothing to do here but downcast for access to
            // commit().
            let newConnection = try await SSHDispatcher.connectHandler(profile: profile) as! JuniperBase
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

    /// Loads `configText` into the candidate configuration, staying in
    /// config mode afterward (`exitConfigMode: false`) so the Commit
    /// section below has something uncommitted to act on.
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

    /// Exits config mode. If there are uncommitted changes, JunOS asks
    /// to confirm discarding them — `exitConfigMode()` answers "yes" on
    /// our behalf, so this is effectively a discard button.
    func discardAndExitConfig() async {
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
            errorMessage = "Invalid commit argument combination."
            return
        }

        errorMessage = nil
        isRunning = true
        output = ""
        defer { isRunning = false }

        do {
            output = try await connection.commit(
                confirm: commitConfirm,
                confirmDelay: Int(commitConfirmDelay),
                check: commitCheck,
                comment: commitComment,
                andQuit: commitAndQuit
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
