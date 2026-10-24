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

1. **`AuthMethod.sshAgent` silently did nothing.** It fell through to an internal `NoAuthDelegate` that offers no authentication method at all, so a connection using it always failed — with a generic, confusing NIOSSH negotiation error, not a clear one. `EXAMPLES.md` claimed it "defers to a running SSH agent," which was never true; swift-nio-ssh has no SSH-agent protocol support to forward to. **Fixed**: using `.sshAgent` now throws `SwiftmikoError.notImplemented` with a clear message pointing at `.keyFile` instead (`Sources/NIOSSHChannel.swift`). Docs corrected. Implementing real SSH-agent support was considered and deliberately deferred — it needs an architectural change to how the vendored NIOSSH fork signs (today a synchronous, local, in-memory operation; agent support means round-tripping over a Unix socket to an external process instead), not just a new code path.

2. **`AuthMethod.keyFile`'s `passphrase:` parameter was dead — now implemented.** `SSHKeyLoader`'s OpenSSH-format parser used to always throw for an encrypted key regardless of whether a passphrase was supplied. **Fixed for real**: `passphrase:` now decrypts OpenSSH's standard bcrypt-kdf + AES-CTR/CBC encrypted keys. This required a from-scratch Blowfish + `bcrypt_pbkdf` port (`Sources/BlowfishKDFSupport.swift`, `Sources/BCryptPBKDF.swift`), transcribed directly from OpenBSD's reference C source (not from memory) and cross-validated against the real Python `bcrypt` package's `bcrypt.kdf(...)` output across 6 password/salt/rounds/keyLength combinations, then verified end-to-end against real `ssh-keygen`-generated encrypted Ed25519 and ECDSA keys (both AES-256-CTR and AES-256-CBC) — decrypting each and confirming the derived key reconstructs the exact matching public key from the real `.pub` file. See `Tests/SwiftmikoTests/BCryptPBKDFTests.swift` and `SSHKeyLoaderTests.swift`.

3. **Host key verification had zero documentation.** `strictHostKeyChecking`/`hostKeyPolicy`/`knownHostsPath` are fully implemented and tested but never appeared anywhere in `EXAMPLES.md`'s table of contents or body. **Fixed**: added a "Host key verification" section to `EXAMPLES.md`.

See `SecureConnectViewModel.swift`'s doc comments for the same detail, inline at point of use.

## Supported key formats

Ed25519, ECDSA (P-256/384/521), and RSA (`ssh-rsa`) in OpenSSH format. SEC1 and PKCS8 PEM support Ed25519/ECDSA only — RSA keys in either PEM format (or classic `-----BEGIN RSA PRIVATE KEY-----` PKCS#1 PEM) throw a clear "not supported" error; re-save in OpenSSH format with `ssh-keygen -p -f <keyfile>` first. Passphrase-protected keys are supported for the OpenSSH format only (the one `ssh-keygen` produces by default); SEC1/PKCS8 PEM keys must be unencrypted.

RSA support required extending the *vendored* NIOSSH fork (`Sources/swift-nio-ssh`), not just Swiftmiko's own code — `NIOSSHPrivateKey` had no RSA case at all; only RSA *host-key verification* existed (an earlier fork addition). The new signing path mirrors that existing precedent (same RFC 4253 §6.6 SHA-1 + PKCS1v1.5 quirk, empirically confirmed against real Cisco IOS on the verification side). It's verified two ways: parsing + public-key reconstruction against a real `ssh-keygen -t rsa` key (`Tests/SwiftmikoTests/SSHKeyLoaderTests.swift`), and a full live signing round trip against a real, independent `asyncssh` Python SSH server — `NIOSSHPrivateKey.sign` is internal to the vendored module and can't be unit-tested directly, so this was the strongest verification available.
