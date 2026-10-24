// Examples/SecureConnectDemo/SecureConnectViewModel.swift
//
// Combines Swiftmiko's two independent "secure connection" features
// into one demo: key-based auth (AuthMethod.keyFile) and known_hosts
// host key verification (ConnectionProfile.strictHostKeyChecking).
// They're unrelated knobs — key auth answers "does the SERVER trust
// ME", host key verification answers "do I trust the SERVER" — but
// both get reached for in the same "I want this connection locked
// down" moment, so one demo covers both.

import Foundation
import Swiftmiko

enum SecureConnectAuthKind: String, CaseIterable, Identifiable {
    case password = "Password"
    case keyFile = "Key File"
    var id: String { rawValue }
}

@MainActor
@Observable
final class SecureConnectViewModel {
    var host = ""
    var port = 22
    var username = ""
    var deviceType = "cisco_ios"
    var command = "show version"

    var authKind: SecureConnectAuthKind = .keyFile
    var password = ""

    /// Supported key formats: Ed25519 and ECDSA (P-256/384/521), in
    /// OpenSSH, SEC1 PEM, or PKCS8 PEM form — see SSHKeyLoader.swift.
    /// RSA throws a clear "not supported" error; passphrase-protected
    /// keys throw regardless of what's passed as `passphrase` below —
    /// that parameter exists on AuthMethod.keyFile but isn't wired to
    /// any decryption yet. Strip it first: ssh-keygen -p -N '' -f <key>.
    var keyPath = "~/.ssh/id_ed25519"
    var keyPassphrase = ""

    var strictHostKeyChecking = false
    var hostKeyPolicy: HostKeyPolicy = .rejectUnknown
    var knownHostsPath = "~/.ssh/known_hosts"

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    var output: String?
    var errorMessage: String?
    var isRunning = false

    func connect() async {
        errorMessage = nil
        output = nil
        isRunning = true
        defer { isRunning = false }

        let auth: AuthMethod
        switch authKind {
        case .password:
            auth = .password(password)
        case .keyFile:
            auth = .keyFile(
                path: keyPath,
                passphrase: keyPassphrase.isEmpty ? nil : keyPassphrase
            )
        }

        let profile = ConnectionProfile(
            host: host,
            port: port,
            deviceType: deviceType,
            username: username,
            auth: auth,
            strictHostKeyChecking: strictHostKeyChecking,
            allowLegacyCiphers: allowLegacyCiphers,
            knownHostsPath: knownHostsPath.isEmpty ? nil : knownHostsPath,
            hostKeyPolicy: hostKeyPolicy
        )

        do {
            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            output = try await connection.sendCommand(command, readTimeout: 30.0)
            await connection.disconnect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
