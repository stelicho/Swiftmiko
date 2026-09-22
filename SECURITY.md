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

### Host key verification is not yet enforced

`ConnectionProfile.strictHostKeyChecking` exists but **is not
currently implemented**. Every SSH connection accepts whatever host
key the remote end presents — see `AcceptAllHostKeysDelegate` in
[`Sources/NIOSSHChannel.swift`](./Sources/NIOSSHChannel.swift), which
unconditionally succeeds host-key validation regardless of that
setting. In its current state, Swiftmiko provides no protection
against a man-in-the-middle presenting a different host key than the
one you connected to previously.

Treat every connection as unauthenticated-server until this is fixed.
Real known-hosts-style validation is a known gap, not a hidden one —
tracked as an open item, and a PR implementing it is welcome (see
[`CONTRIBUTING.md`](./CONTRIBUTING.md)).

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
