# SecureConnectDemo

Combines Swiftmiko's two independent "secure connection" knobs into one demo:

- **Key-based authentication** (`AuthMethod.keyFile`) — does the *server* trust *me*.
- **known_hosts host key verification** (`ConnectionProfile.strictHostKeyChecking`) — do *I* trust the *server*.

They're unrelated settings, but both get reached for in the same "I want this connection locked down" moment, so one demo covers both side by side.

## What it demonstrates

- Toggling between password and key-file auth via `AuthMethod`.
- `ConnectionProfile.strictHostKeyChecking`, `.hostKeyPolicy` (`.rejectUnknown` vs `.autoAdd`), and `.knownHostsPath` — a real, fully-implemented OpenSSH-`known_hosts`-backed verification layer (`Sources/KnownHosts.swift`) that was previously undocumented anywhere in `EXAMPLES.md`.

## Real gaps found while building this (all fixed or documented)

Building this surfaced three issues in the SSH-auth surface, none of which were about this demo's own code — all in the library/docs it depends on:

1. **`AuthMethod.sshAgent` silently did nothing.** It fell through to an internal `NoAuthDelegate` that offers no authentication method at all, so a connection using it always failed — with a generic, confusing NIOSSH negotiation error, not a clear one. `EXAMPLES.md` claimed it "defers to a running SSH agent," which was never true; swift-nio-ssh has no SSH-agent protocol support to forward to. **Fixed**: using `.sshAgent` now throws `SwiftmikoError.notImplemented` with a clear message pointing at `.keyFile` instead (`Sources/NIOSSHChannel.swift`). Docs corrected.

2. **`AuthMethod.keyFile`'s `passphrase:` parameter was dead.** `SSHKeyLoader`'s OpenSSH-format parser always throws for an encrypted key, regardless of whether a passphrase was supplied — the parameter is accepted but never used to attempt decryption, and no other supported format (SEC1/PKCS8 PEM) even receives it. Not a crash or silent wrong behavior (an encrypted key still fails with a clear error either way), but the public API's shape implied passphrase support that doesn't exist. **Documented** with an explicit doc comment on `AuthMethod.keyFile` and a correction in `EXAMPLES.md`, rather than attempting a real passphrase-decryption implementation (a nontrivial crypto feature — bcrypt KDF + cipher decrypt — out of scope for a docs/demo pass).

3. **Host key verification had zero documentation.** `strictHostKeyChecking`/`hostKeyPolicy`/`knownHostsPath` are fully implemented and tested but never appeared anywhere in `EXAMPLES.md`'s table of contents or body. **Fixed**: added a "Host key verification" section to `EXAMPLES.md`.

See `SecureConnectViewModel.swift`'s doc comments for the same detail, inline at point of use.

## Supported key formats

Ed25519 and ECDSA (P-256/384/521), in OpenSSH, SEC1 PEM, or PKCS8 PEM form. RSA throws a clear "not supported" error (`ssh-keygen -t ed25519` is the suggested conversion) — `SSHKeyLoader.swift` documents this as a deliberate limitation, not an oversight.
