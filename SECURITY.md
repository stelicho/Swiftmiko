# Security Policy

Swiftmiko is **pre-alpha** (see [`README.md`](./README.md)) and talks
directly to network device management interfaces over SSH/Telnet.
This document covers two things: security tradeoffs that are already
known and intentional, and how to report anything else.

## Known, accepted risks

These are documented so you can make an informed call about your own
usage — they are not something you need to report.

### Legacy SSH ciphers (`allowLegacyCiphers`)

`ConnectionProfile.allowLegacyCiphers` is **off by default**. When
enabled, it adds AES-CBC transport ciphers to the SSH handshake
alongside the modern AES-GCM ones, for old device images (aging Cisco
IOS crypto images, mostly) that never implemented AES-GCM and would
otherwise be unreachable.

AES-CBC-mode SSH has known weaknesses — most notably plaintext-recovery
attacks against the CBC construction as used in the SSH protocol.
Enabling this flag is a deliberate downgrade, and it should only be
used against lab, EOL, or otherwise fully-trusted gear that you
control and cannot upgrade. Don't enable it for anything reachable by
or routed through a network you don't fully trust.

### Host key verification is opt-in, not on by default

`ConnectionProfile.strictHostKeyChecking` defaults to `false`, in
which case every SSH connection still accepts whatever host key the
remote end presents (`AcceptAllHostKeysDelegate` in
[`Sources/NIOSSHChannel.swift`](./Sources/NIOSSHChannel.swift)) — no
protection against a man-in-the-middle presenting a different host
key than the device actually has. That default is deliberate: it
matches this library's lab/dev-oriented posture, where devices get
re-imaged and re-keyed constantly and verifying against a stale key
would just be friction.

Set `strictHostKeyChecking = true` to turn this on for real. Doing so
checks every presented host key against an OpenSSH-format
`known_hosts` file (`ConnectionProfile.knownHostsPath`, defaulting to
`~/.ssh/known_hosts`) via `KnownHostsValidatingDelegate` in
[`Sources/KnownHosts.swift`](./Sources/KnownHosts.swift). A key that
contradicts an *existing* entry for that host is always rejected —
regardless of `hostKeyPolicy` — since that's the actual
MITM-detection property. A host with no entry at all is handled by
`hostKeyPolicy`: `.rejectUnknown` (the default) refuses it;
`.autoAdd` trusts it on first connection and records it for next
time (`ssh -o StrictHostKeyChecking=accept-new` semantics).

Residual gaps in the `known_hosts` support itself, by design rather
than oversight: no wildcard (`*`/`?`) or `!negated` host patterns, no
`@cert-authority`/`@revoked` markers. Lines using any of those are
skipped during parsing (never mismatched, never silently trusted) —
see the doc comment on `KnownHostsStore` for the reasoning. None of
these are common in hand-maintained network-device inventories; if
your `known_hosts` file relies on them for the hosts you're
connecting to, the affected entries won't be found and you'll either
need to flatten them to explicit host lines or treat this as still
unprotected for those hosts specifically.

## Reporting a vulnerability

For anything else — a bug that could lead to credential exposure,
memory safety issues in the SSH/SCP transport, an authentication
bypass, or similar — please use GitHub's private vulnerability
reporting instead of opening a public issue:

1. Go to the [Security tab](https://github.com/stelicho/Swiftmiko/security) of this repository.
2. Click **Report a vulnerability**.

This opens a private advisory visible only to you and the maintainer,
so the issue isn't public before a fix is available. Please include:

- The affected version/commit
- Steps to reproduce, or a minimal example
- What you'd expect to happen vs. what actually happens
- Impact, as best you can assess it

Given this project's current pre-alpha status and volunteer
maintenance, please allow some time for a response — but you will get
one.

## Scope

This policy covers the Swiftmiko package itself
(`Sources/`) and its CLI tools (`Sources/CLITools/`). The vendored
[swift-nio-ssh](./Sources/swift-nio-ssh) fork carries its own upstream
security process; issues specific to unmodified upstream code should
go to that project instead.
