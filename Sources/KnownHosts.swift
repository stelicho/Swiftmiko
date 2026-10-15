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
//  KnownHosts.swift
//  Swiftmiko
//
//  OpenSSH known_hosts-backed host key verification.
//
//  Previously, EVERY connection — regardless of
//  ConnectionProfile.strictHostKeyChecking — accepted any host key
//  unconditionally via AcceptAllHostKeysDelegate (see
//  NIOSSHChannel.swift), with a TODO noting the flag wasn't actually
//  wired to anything. That made strictHostKeyChecking = true a no-op:
//  no defense against a MITM silently swapping in its own host key.
//
//  This file makes the flag real. When false (the default, unchanged
//  from before), AcceptAllHostKeysDelegate is still used — that
//  default is deliberately permissive for lab/dev use against
//  freshly-provisioned or re-imaged gear, where the host key changes
//  constantly and verifying it against anything is actively
//  unhelpful. When true, every host key is checked against an
//  OpenSSH-format known_hosts file, with a real reject for a key that
//  doesn't match an EXISTING entry — that's the actual MITM-detection
//  property, and it holds regardless of hostKeyPolicy.
//

import Foundation
import NIOSSH
import NIOCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// MARK: - Host key policy

/// What to do when `strictHostKeyChecking` is true and a host has no
/// existing known_hosts entry at all. Mirrors the Paramiko/Netmiko
/// distinction between `RejectPolicy` and `AutoAddPolicy`.
///
/// Neither case changes behavior for a host that DOES have an
/// existing entry: a presented key that doesn't match any entry on
/// file is always rejected by `KnownHostsValidatingDelegate`,
/// regardless of this setting.
public enum HostKeyPolicy: Sendable {
    /// Reject any host with no existing known_hosts entry. The secure
    /// default: equivalent to `ssh -o StrictHostKeyChecking=yes`.
    case rejectUnknown

    /// Trust-on-first-use: accept an unknown host's key and append it
    /// to the known_hosts file so future connections are verified
    /// against it. Equivalent to `ssh -o StrictHostKeyChecking=accept-new`.
    case autoAdd
}

// MARK: - KnownHostsStore

/// Minimal OpenSSH known_hosts reader/writer.
///
/// Supports plain comma-separated hostname entries and hashed entries
/// (`|1|salt|hash`), including the `[host]:port` bracket notation
/// OpenSSH uses for non-default ports. Does NOT support wildcard
/// (`*`/`?`) patterns, `!negated` patterns, or `@cert-authority`/
/// `@revoked` markers — none of those are common in hand-maintained
/// network-device inventories, and silently mis-handling a wildcard
/// would be worse than refusing to match it at all. Lines using any
/// of those features are skipped during parsing (treated as neither a
/// match nor an error).
struct KnownHostsStore {
    let path: String

    init(path: String) {
        self.path = path
    }

    private struct Entry {
        let plainHosts: [String]
        let hashedHosts: [HashedHostPattern]
        let publicKey: NIOSSHPublicKey
    }

    /// All keys on file for `host:port`, trying both the bare hostname
    /// and the bracketed `[host]:port` form so entries written by
    /// either this store or by hand (which might ignore port) still
    /// match.
    func keys(forHost host: String, port: Int) -> [NIOSSHPublicKey] {
        let bracketed = "[\(host)]:\(port)"
        return entries().compactMap { entry -> NIOSSHPublicKey? in
            if entry.plainHosts.contains(host) || entry.plainHosts.contains(bracketed) {
                return entry.publicKey
            }
            if entry.hashedHosts.contains(where: { $0.matches(host) || $0.matches(bracketed) }) {
                return entry.publicKey
            }
            return nil
        }
    }

    /// Append a new entry. Always writes the bracketed `[host]:port`
    /// form when `port != 22`, matching the convention OpenSSH itself
    /// uses, so a later lookup against the same port matches.
    func append(host: String, port: Int, key: NIOSSHPublicKey) throws {
        let hostField = port == 22 ? host : "[\(host)]:\(port)"
        let line = "\(hostField) \(String(openSSHPublicKey: key))\n"

        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try? FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true
            )
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        guard let data = line.data(using: .utf8) else { return }
        handle.write(data)
    }

    // MARK: Parsing

    private func entries() -> [Entry] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        return contents
            .components(separatedBy: .newlines)
            .compactMap(Self.parseLine)
    }

    private static func parseLine(_ rawLine: String) -> Entry? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("@") else {
            return nil
        }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3 else { return nil }

        let hostsField = String(fields[0])
        guard !hostsField.contains("*"), !hostsField.contains("?"), !hostsField.hasPrefix("!") else {
            // Wildcard / negated pattern — not supported, skip rather than mis-match.
            return nil
        }

        let openSSHKeyString = "\(fields[1]) \(fields[2])"
        guard let publicKey = try? NIOSSHPublicKey(openSSHPublicKey: openSSHKeyString) else {
            return nil
        }

        if hostsField.hasPrefix("|1|") {
            guard let hashed = HashedHostPattern(token: hostsField) else { return nil }
            return Entry(plainHosts: [], hashedHosts: [hashed], publicKey: publicKey)
        }

        let plainHosts = hostsField.split(separator: ",").map(String.init)
        return Entry(plainHosts: plainHosts, hashedHosts: [], publicKey: publicKey)
    }

    // MARK: Default location

    static func defaultPath() -> String {
        NSHomeDirectory() + "/.ssh/known_hosts"
    }
}

// MARK: - Hashed hostname entries

/// A single `|1|salt|hash` known_hosts entry — OpenSSH's
/// HashKnownHosts format, an HMAC-SHA1 of the hostname keyed by a
/// random per-entry salt. SHA1 here is mandated by the on-disk format
/// itself, not a cryptographic choice made by this code.
private struct HashedHostPattern {
    let salt: Data
    let hash: Data

    init?(token: String) {
        let parts = token.components(separatedBy: "|")
        // "|1|saltB64|hashB64" splits into ["", "1", saltB64, hashB64].
        guard parts.count == 4, parts[1] == "1",
              let salt = Data(base64Encoded: parts[2]),
              let hash = Data(base64Encoded: parts[3]) else {
            return nil
        }
        self.salt = salt
        self.hash = hash
    }

    func matches(_ hostText: String) -> Bool {
        let key = SymmetricKey(data: salt)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(hostText.utf8), using: key)
        return Data(mac) == hash
    }
}

// MARK: - Fingerprint display

enum HostKeyFingerprint {
    /// SHA256 fingerprint in OpenSSH's display format ("SHA256:...",
    /// base64 without padding) — computed from the key's own OpenSSH
    /// wire encoding, since `String(openSSHPublicKey:)` is the only
    /// public serialization NIOSSHPublicKey exposes outside its own
    /// module (the raw key blob and `keyPrefix` are both internal).
    static func describe(_ key: NIOSSHPublicKey) -> String {
        let openSSHString = String(openSSHPublicKey: key)
        guard let base64Part = openSSHString.split(separator: " ", maxSplits: 1).dropFirst().first,
              let raw = Data(base64Encoded: String(base64Part)) else {
            return "<unprintable key>"
        }
        let digest = SHA256.hash(data: raw)
        let encoded = Data(digest).base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(encoded)"
    }
}

// MARK: - KnownHostsValidatingDelegate

/// NIOSSHClientServerAuthenticationDelegate backing
/// `ConnectionProfile.strictHostKeyChecking = true`.
///
/// A host with NO existing known_hosts entry is handled per `policy`.
/// A host WITH existing entries, none of which match the presented
/// key, is ALWAYS rejected regardless of policy — that mismatch is
/// exactly what host key checking exists to catch (a changed key is
/// either a legitimate device re-key/reinstall or a MITM, and this
/// layer can't tell those apart, so it never guesses which).
///
/// NIOSSHClientServerAuthenticationDelegate.validateHostKey receives
/// only the key itself, not a host/port — so host/port are captured
/// at construction time, once per connection, rather than threaded
/// through the validation call.
final class KnownHostsValidatingDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let store: KnownHostsStore
    private let policy: HostKeyPolicy

    init(host: String, port: Int, knownHostsPath: String, policy: HostKeyPolicy) {
        self.host = host
        self.port = port
        self.store = KnownHostsStore(path: knownHostsPath)
        self.policy = policy
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let existing = store.keys(forHost: host, port: port)

        if existing.contains(hostKey) {
            validationCompletePromise.succeed(())
            return
        }

        guard existing.isEmpty else {
            validationCompletePromise.fail(SwiftmikoError.connectionFailed(
                "Host key verification FAILED for \(host):\(port) — the presented key " +
                "(\(HostKeyFingerprint.describe(hostKey))) does not match any key already " +
                "trusted for this host in \(store.path). This could mean the device's host " +
                "key legitimately changed (reinstall, replacement) OR that the connection is " +
                "being intercepted. Verify the new key out-of-band before removing the old " +
                "entry from known_hosts."
            ))
            return
        }

        switch policy {
        case .rejectUnknown:
            validationCompletePromise.fail(SwiftmikoError.connectionFailed(
                "No known_hosts entry for \(host):\(port) and hostKeyPolicy is .rejectUnknown. " +
                "Presented key: \(HostKeyFingerprint.describe(hostKey)). Verify it out-of-band " +
                "and add it to \(store.path) yourself, or set " +
                "profile.hostKeyPolicy = .autoAdd to trust it automatically on first connect."
            ))
        case .autoAdd:
            do {
                try store.append(host: host, port: port, key: hostKey)
                validationCompletePromise.succeed(())
            } catch {
                validationCompletePromise.fail(SwiftmikoError.connectionFailed(
                    "Could not write new known_hosts entry for \(host):\(port) to \(store.path): \(error)"
                ))
            }
        }
    }
}

// MARK: - Delegate selection

enum HostKeyVerification {
    /// Resolves the right NIOSSHClientServerAuthenticationDelegate for
    /// a connection profile — AcceptAllHostKeysDelegate when
    /// `strictHostKeyChecking` is false (the default, unchanged
    /// behavior), or a KnownHostsValidatingDelegate backed by
    /// `profile.knownHostsPath` (defaulting to `~/.ssh/known_hosts`)
    /// when it's true.
    static func delegate(
        for profile: ConnectionProfile
    ) -> any NIOSSHClientServerAuthenticationDelegate & Sendable {
        guard profile.strictHostKeyChecking else {
            return AcceptAllHostKeysDelegate()
        }
        return KnownHostsValidatingDelegate(
            host: profile.host,
            port: profile.port,
            knownHostsPath: profile.knownHostsPath ?? KnownHostsStore.defaultPath(),
            policy: profile.hostKeyPolicy
        )
    }
}
