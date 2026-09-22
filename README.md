# README.md

<p align="center">
  <img src="./Images/SwiftMikoLogo.jpg" alt="Swiftmiko logo" width="320">
</p>

<h1 align="center">Swiftmiko</h1>

<p align="center">
  <a href="https://github.com/stelicho/Swiftmiko/actions/workflows/ci.yml">
    <img src="https://github.com/stelicho/Swiftmiko/actions/workflows/ci.yml/badge.svg" alt="CI status">
  </a>
</p>

<p align="center">
  A native Swift port of <a href="https://github.com/ktbyers/netmiko">Netmiko</a> —
  multi-vendor network device SSH/Telnet automation, built for Swift and Apple platforms.
</p>

---

## What Is This?

Swiftmiko brings Netmiko's device-abstraction model to Swift:
one consistent API — `connect()`, `sendCommand(_:)`, `sendConfigSet(_:)`,
`enterEnableMode(secret:)` — across 150+ network vendor CLIs, from
Cisco IOS to Juniper JunOS to MikroTik RouterOS to Nokia SR OS and
far beyond. If you already know Netmiko, Swiftmiko should feel
immediately familiar; if you're coming from Swift, it should feel
like a normal, modern async Swift library.

```swift
import Swiftmiko

let profile = ConnectionProfile(
    host: "192.168.1.1",
    deviceType: "cisco_ios",
    username: "admin",
    auth: .password("changeme")
)

let connection = try await SSHDispatcher.connectHandler(profile: profile)
try await connection.enterEnableMode(secret: "enablepass")
let output = try await connection.sendCommand("show version")
print(output)
await connection.disconnect()
```

## Status

**This project is under active development and has not yet been
verified against real or emulated hardware.** Every driver listed in
[`PLATFORMS.md`](./PLATFORMS.md) has been translated from Netmiko's
Python source and compiles against Swiftmiko's core API, but none has
been confirmed working end-to-end yet. Testing against GNS3 and real
devices is actively in progress — see `PLATFORMS.md` for the current
per-platform status and how to help verify one.

Treat this as **pre-alpha**. APIs may change without notice until the
first tagged release.

## Getting Started

### Requirements

- Xcode 16+ / Swift 5.9+
- macOS 14+ (for the library target)

### Installing

Swiftmiko is a Swift Package. Add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/stelicho/Swiftmiko.git", branch: "main")
]
```

Or in Xcode: **File → Add Package Dependencies...** and paste the
repository URL.

### Examples

The `Examples/` directory contains several small SwiftUI apps
demonstrating real usage against real devices — a VLAN viewer, an
enable-mode demo, a running-config fetcher, a multi-vendor command
runner, and an Open vSwitch topology browser. Each is its own Xcode
target; open `Swiftmiko.xcworkspace` (or the project directly) and
switch schemes to try one.

## Documentation

- [`PLATFORMS.md`](./PLATFORMS.md) — full list of supported device
  types and their current testing status
- [`EXAMPLES.md`](./EXAMPLES.md) — common connection patterns: enable
  mode, config changes, session logging, SCP, SSH/SNMP autodetection,
  terminal servers
- [`VENDOR.md`](./VENDOR.md) — how to add a new vendor driver
- [`TESTING.md`](./TESTING.md) — the test suite, and how to verify a
  platform against real/emulated hardware
- [`ENCRYPTION_HANDLING.md`](./ENCRYPTION_HANDLING.md) — encrypting
  credentials in `.swiftmiko.yml` for the CLI tools
- [`COMMON_ISSUES.md`](./COMMON_ISSUES.md) — FAQ and known gaps
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — how to build, test, and
  submit a change
- Inline documentation comments throughout the source explain how
  each driver maps back to its corresponding file in Netmiko's own
  codebase, including notes on any behavioral differences

## Relationship to Netmiko

Swiftmiko is a from-scratch reimplementation, not a wrapper or
bridge — there is no Python runtime involved anywhere. Every driver
was translated by hand from Netmiko's actual source, preserving
vendor-specific quirks, workarounds, and (where found) even genuine
upstream bugs, each called out explicitly in code comments rather
than silently "fixed," since a silent fix risks changing behavior
that hasn't been validated against real hardware. Full credit to
[Kirk Byers](https://github.com/ktbyers) and the Netmiko community —
this project exists because that one does.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). The single most valuable
thing right now is testing a platform against real or emulated
hardware and reporting back — especially anything still marked ⬜
Untested in [`PLATFORMS.md`](./PLATFORMS.md).

## License

MIT
