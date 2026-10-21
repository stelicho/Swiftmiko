# Testing

This document covers the test suite for Swiftmiko: the unit tests
that run without any device, and how to verify a driver against a
real or emulated one.

## Unit tests (no device required)

Swiftmiko's unit tests live in `Tests/SwiftmikoTests/` (core library)
and `Tests/SwiftmikoCLITests/` (the CLI tools target, `SwiftmikoCLI`)
and run against one of two in-memory fake channels
(`Sources/Channel.swift`) — no network connection involved:

- **`BufferedChannel`** — enqueue canned output, drain it all in one
  shot. Use this for a single request/response or when you just need
  to inspect what a driver wrote.
- **`ScriptedChannel`** (`Tests/SwiftmikoTests/ScriptedChannel.swift`)
  — returns exactly one scripted response per read call, in order.
  Use this for anything with a multi-step exchange (enable mode,
  config mode, login sequences) where a driver reads the channel more
  than once — the response list has to line up 1:1 with however many
  times the driver under test actually reads.

```bash
swift test
```

Existing tests to use as a model:

- `BaseConnectionTests.swift` — exercises `sendCommand`'s
  echo/prompt-stripping against a fake channel. Follow this pattern
  when adding coverage for a new driver (see
  [`VENDOR.md`](./VENDOR.md) step 5).
- `DriverRegressionTests.swift` — the single largest test file in the
  suite, and the primary pattern used throughout a full adversarial
  review comparing every driver against real Netmiko source: one test
  per bug found, scripting the exact exchange that was missing/wrong
  (a silently no-op'd config-mode call, a missing `disablePaging()`
  override, a wrong default regex, etc.) and asserting the real
  command actually gets sent. This is the model to copy for "I found
  a translation bug" coverage, as opposed to "I'm adding a brand new
  driver" coverage (which `VENDOR.md` step 5 covers).
- `NoEnableEnforcementTests.swift` / `NoConfigEnforcementTests.swift`
  — Swift has no MRO, so a class conforming to the `NoEnable`/
  `NoConfig` marker protocols needs its own direct override of each
  relevant method (a protocol extension default is never reached —
  see the file comment on `Sources/NoEnable.swift` for the confirmed
  repro). These tests construct a representative sample of
  conforming classes with no channel at all and assert the trivial
  pass-through behavior, proving the marker protocol's real behavior
  is reachable rather than silently falling through to
  `BaseConnection`'s own throwing/no-op default.
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
  when adding a new dispatcher entry per [`VENDOR.md`](./VENDOR.md) —
  it's also what caught a real bug once: 15 dispatcher entries
  silently constructing a generic fallback class instead of their own
  dedicated one.
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
  injectable protocol rather than a concrete transport (see also
  `Examples/SNMPDemo`'s `MinimalSNMPGetTransport`, a *real* — not
  mocked — implementation of that same protocol).
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
- `Tests/SwiftmikoCLITests/` — a separate target for `Sources/CLITools/`
  (the `swiftmiko-show`/`-cfg`/`-grep`/`-encrypt`/`-bulk-encrypt`
  tools), `@testable import SwiftmikoCLI` rather than `Swiftmiko`.
  `CLIEncryptionTests.swift` checks wire-compatibility against real
  Netmiko-generated ciphertext vectors; `OutputtersTests.swift` and
  `DeviceInventoryTests.swift` cover the CLI's own pure logic (output
  formatting, device/group inventory resolution). `DeviceInventoryTests`
  is the model for testing anything that reads from an environment
  variable (`$SWIFTMIKO_TOOLS_CFG` here) — point it at a temp file for
  the duration of one test using the cross-platform `setenv`/
  `_putenv_s` helper pattern there (POSIX `setenv` doesn't exist on
  Windows' `ucrt`).

### Verifying a new regression test actually catches its bug

Writing a test that merely *passes* against already-correct code
doesn't prove much — it needs to *fail* against the pre-fix code too,
or it might be asserting something that was never actually broken.
The pattern used throughout this project's driver-bug-hunting passes:

```bash
git stash push -m "verify regression test" -- path/to/FixedFile.swift
# run just the new test — confirm it now fails, with the predicted
# failure mode (wrong output, a thrown error, a timeout)
git stash pop
```

For a batch of several independent fixes at once, `git stash push --
<file1> <file2> ...` reverts all of them together, so every
corresponding test can be run and confirmed failing in one pass rather
than one file at a time.

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
