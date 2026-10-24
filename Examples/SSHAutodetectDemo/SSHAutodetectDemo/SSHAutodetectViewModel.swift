// Examples/SSHAutodetectDemo/SSHAutodetectViewModel.swift
import Foundation
import Swiftmiko

@MainActor
@Observable
final class SSHAutodetectViewModel {
    var host = ""
    var username = ""
    var password = ""

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    var bestMatch: String?
    var potentialMatches: [(deviceType: String, score: Int)] = []
    var verificationOutput: String?

    var isDetecting = false
    var isVerifying = false
    var errorMessage: String?

    func detect() async {
        errorMessage = nil
        bestMatch = nil
        potentialMatches = []
        verificationOutput = nil
        isDetecting = true
        defer { isDetecting = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                // "generic_termserver" resolves to TerminalServerSSH,
                // whose sessionPreparation() is a deliberate no-op (no
                // paging-disable command, no base-prompt detection) —
                // unlike probing with a real vendor driver (e.g.
                // "cisco_ios", as EXAMPLES.md's own snippet does), this
                // can't send the wrong vendor's setup commands at an
                // unknown device or hang waiting for a prompt shape
                // that device will never produce. SSHDetect only needs
                // a live, authenticated connection to read from —
                // nothing about session prep matters to it.
                deviceType: "generic_termserver",
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )

            let probe = try await SSHDispatcher.connectHandler(profile: profile)
            let guesser = try await SSHDetect(connection: probe)

            // autodetect() disconnects `probe` itself before returning,
            // on every code path — calling connection.disconnect() on
            // it afterward would be redundant (and the reason there's
            // no `defer { await probe.disconnect() }` above).
            bestMatch = await guesser.autodetect()
            potentialMatches = guesser.potentialMatches
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { (deviceType: $0.key, score: $0.value) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func verifyDetectedType() async {
        guard let bestMatch else { return }
        errorMessage = nil
        verificationOutput = nil
        isVerifying = true
        defer { isVerifying = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: bestMatch,
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            verificationOutput = try await connection.findPrompt()
            await connection.disconnect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
