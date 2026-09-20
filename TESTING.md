# Testing

This document covers the test suite for Swiftmiko: the unit tests
that run without any device, and how to verify a driver against a
real or emulated one.

## Unit tests (no device required)

Swiftmiko's unit tests live in `Tests/SwiftmikoTests/` and run
against `BufferedChannel` — an in-memory fake channel
(`Sources/Channel.swift`) that lets a test enqueue canned device
output and inspect what a driver wrote, with no network connection
involved.

```bash
swift test
```

Existing tests to use as a model:

- `BaseConnectionTests.swift` — exercises `sendCommand`'s
  echo/prompt-stripping against a fake channel. Follow this pattern
  when adding coverage for a new driver (see
  [`VENDOR.md`](./VENDOR.md) step 5).
- `GlobalCmdVerifyInitTests.swift` — uses the `swift-testing`
  `@Test`/`#expect` style rather than `XCTest`; either is fine for new
  tests, but match whichever style the file you're extending already
  uses.
- `LegacyCBCTransportProtectionTests.swift` — a lower-level example
  that exercises the legacy AES-CBC transport path
  (`allowLegacyCiphers`) directly against `swift-crypto`/`NIOSSH`
  primitives, independent of any device driver.
- `SSHDispatcherRegistryTests.swift` — constructs every `deviceType`
  registered in `SSHDispatcher.defaultConnectionFactories` and checks
  it builds a live instance with the right `deviceType`, with no
  network I/O. This is the test to extend (or that will catch you)
  when adding a new dispatcher entry per [`VENDOR.md`](./VENDOR.md).
- `SCPDispatcherRegistryTests.swift` — the same idea for
  `defaultFileTransferFactories`, using a real local temp file with
  `direction: .put` (the one combination `SCPHandler.init` can
  complete without a network round trip) so the type-cast-dependent
  factories (`dell_sonic`, `nokia_sros`, `zpe_nodegrid`) are actually
  exercised, not just assumed to compile.
- `RedispatchTests.swift` — proves `SSHDispatcher.redispatch` reuses
  the original connection's channel (via a shared `BufferedChannel`)
  rather than opening a new one.
- `SNMPAutodetectTests.swift` — exercises `SNMPDetect`'s priority/
  tiebreak matching and response caching against a mock
  `SNMPTransport`, the SNMP equivalent of `BufferedChannel` for SSH.
  Good model for testing anything else built around a small,
  injectable protocol rather than a concrete transport.
- `SerialChannelTests.swift` — `SerialChannel` talks directly to a
  POSIX tty (no injectable protocol to fake), so this covers what's
  actually testable without real hardware: `SerialSettings` as a
  plain value type, `SerialChannel`'s own error handling (bad port
  path, using it before `open()`), `SSHDispatcher`'s `_serial`-suffix
  channel routing (via `connectHandler(profile:autoConnect:false)`,
  so it never touches a real port), and the CLI driver logic
  (`CiscoIOSSerial`) against a `BufferedChannel` — a driver's
  `sendCommand`/prompt handling is transport-agnostic, so it's tested
  the same way regardless of whether the real channel underneath is
  SSH, Telnet, or serial.

## Verifying a platform against real or emulated hardware

This is the testing Swiftmiko actually needs most right now — see
[`PLATFORMS.md`](./PLATFORMS.md). Every driver compiles; almost none
has been confirmed against a real device.

1. Get access to the device — GNS3, a vendor's free lab/cloud image
   (vEOS, CHR, vSRX, etc.), or real hardware.
2. Connect with the driver under test:

   ```swift
   import Swiftmiko

   let profile = ConnectionProfile(
       host: "192.168.1.1",
       deviceType: "arista_eos",
       username: "admin",
       auth: .password("changeme")
   )
   let connection = try await SSHDispatcher.connectHandler(profile: profile)
   print(try await connection.sendCommand("show version"))
   await connection.disconnect()
   ```

3. Confirm, at minimum: `connect()` succeeds, session preparation
   (paging disabled, base prompt set) doesn't hang or error, and one
   `sendCommand` round-trip returns clean output with the command
   echo and prompt stripped.
4. Update that platform's row in [`PLATFORMS.md`](./PLATFORMS.md)
   from ⬜ to 🟨 (in progress) or ✅ (verified), or to ⚠️ with a linked
   issue if you found a real bug.
5. Open a PR with the status update. Include what you tested against
   (device/image and version) in the description.

See [`EXAMPLES.md`](./EXAMPLES.md) for more connection patterns
(enable mode, config changes, session logging, SCP, autodetection)
to exercise while verifying a platform.
