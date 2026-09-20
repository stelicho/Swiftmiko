# Contributing to Swiftmiko

Thanks for considering a contribution. Swiftmiko is a from-scratch
Swift port of [Netmiko](https://github.com/ktbyers/netmiko), and it's
currently **pre-alpha** — see [`README.md`](./README.md) and
[`PLATFORMS.md`](./PLATFORMS.md) for the current state. The single
most valuable thing you can do right now is test a platform against
real or emulated hardware and report back.

## Ways to contribute

- **Verify a platform.** Every driver in [`PLATFORMS.md`](./PLATFORMS.md)
  compiles but is marked ⬜ Untested until someone confirms it against
  GNS3 or real hardware. Pick one, connect, run a `sendCommand`
  round-trip, and open a PR flipping its status (see
  [`TESTING.md`](./TESTING.md)).
- **Port a missing vendor.** If a device type exists in Netmiko but
  not yet in Swiftmiko, see [`VENDOR.md`](./VENDOR.md) for the steps
  to add a new driver.
- **Fix a translation bug.** Every driver was translated by hand from
  Netmiko's Python source. Behavioral differences from the original
  are called out in code comments rather than silently patched — if
  you find one that's a genuine translation mistake (not an
  intentional Swift-idiom change), fix it and reference the
  corresponding Netmiko source file in the PR description.
- **Improve documentation.** The files in this repo's root are being
  brought up to date from their Netmiko origins one at a time; if you
  spot a doc that's still describing Python/Netmiko behavior instead
  of Swiftmiko's, a PR fixing it is welcome.

## Building and testing

Swiftmiko is a standard Swift Package.

```bash
swift build
swift test
```

Xcode users can open the package directory directly (`open
Package.swift`) or the `Examples/` targets, which are ordinary Xcode
projects that depend on the local package.

### Requirements

- Swift 5.9+ / Xcode 16+
- macOS 14+ (library target)

## Code style

- PascalCase for types, camelCase for properties and methods.
- 4-space indentation.
- Avoid force-unwrapping; prefer Swift's type system over defensive
  runtime checks.
- Prefer `async`/`await` over Combine or completion handlers.
- Default to no comments. When a driver has a genuine quirk,
  workaround, or upstream bug carried over from Netmiko, say so in a
  short comment — that context is exactly what a translation like
  this needs to stay trustworthy, since the behavior can't yet be
  checked against real hardware.

## Submitting a change

1. Fork and branch from `main`.
2. Keep the change scoped — a driver fix doesn't need to refactor
   `BaseConnection`, and a doc fix doesn't need to touch code.
3. Run `swift test` locally before opening the PR.
4. Describe *what you verified it against* (GNS3 image/version, real
   hardware model, or "compiles only") — this project's biggest open
   question is what actually works, so that detail matters more than
   usual.
5. Open a PR against `main`.

## Reporting issues

Open a GitHub issue with:
- The `deviceType` and platform/OS version involved.
- Whether you were testing against real hardware, GNS3, or another
  emulator.
- The relevant `sendCommand`/`sendConfigSet` call and its output
  (redact credentials).

## License

By contributing, you agree your contribution is licensed under this
project's MIT license (see [`LICENSE`](./LICENSE)).
