# Adding a New Vendor Driver

This is the Swiftmiko equivalent of Netmiko's own "adding a new
driver" guide, updated for Swift's type system and this project's
actual `Sources/` layout. It maps directly onto Netmiko's own
vendor-directory structure — `netmiko/<vendor>/<vendor>_ssh.py`
becomes `Sources/<Vendor>/<Vendor><Platform>.swift`.

## 1. Create the vendor directory and file

Every vendor gets its own directory directly under `Sources/`. Follow
the casing already used by existing vendors (e.g. `Sources/Arista/`,
`Sources/Juniper/`).

```
Sources/
  Arista/
    Arista.swift
```

There's no package-init file to create — SwiftPM discovers every
`.swift` file under `Sources/` automatically as part of the
`Swiftmiko` target (see `Package.swift`; only `CLITools`,
`CCommonCryptoShim`, and the vendored `swift-nio-ssh` fork are
excluded, since each of those is its own separate target/package).

## 2. Subclass the right base class

Pick a superclass based on how close the vendor's CLI is to Cisco
IOS:

- **`BaseConnection`** — fully generic. Use this for a vendor with
  its own prompt/paging/config-mode conventions unrelated to Cisco.
- **`CiscoBaseConnection`** — inherits enable-mode, config-mode, save,
  and Cisco-style prompt handling. Use this for anything that
  imitates IOS (which, per Netmiko's own history, is most vendors).
- **`CiscoSSHConnection`** — a `CiscoBaseConnection` with no further
  overrides; if a driver in Netmiko was `class FooSSH(CiscoSSHConnection): pass`,
  the Swift equivalent is exactly that:

```swift
// Sources/Arista/Arista.swift
//
// Port of netmiko/arista/arista_ssh.py

import Foundation

open class AristaSSH: CiscoSSHConnection {}
```

Only override what the vendor's CLI actually does differently. As
much as possible, rely on the inherited behavior from
`CiscoBaseConnection`/`BaseConnection` — re-implementing something
that's already correct in the base class is how translation bugs get
introduced.

## 3. Override only what's different

The methods you're most likely to need to override, all declared
`open` on `BaseConnection` (see `Sources/BaseConnection.swift`) or
`CiscoBaseConnection` (see `Sources/CiscoBaseConnection.swift`):

```swift
func sessionPreparation() async throws       // terminal setup, paging, base prompt
func disablePaging(command:delay:cmdVerify:pattern:) async throws -> String
func setBasePrompt(primaryTerminator:altTerminator:delay:pattern:) async throws
func findPrompt(delay:) async throws -> String
func enterEnableMode(secret:command:pattern:...) async throws -> String
func enterConfigMode(command:pattern:dotAll:) async throws -> String
func exitConfigMode(exitConfig:pattern:) async throws -> String
func sendCommand(_:readTimeout:expectString:stripPrompt:stripCommand:cmdVerify:autoFindPrompt:) async throws -> String
func sendConfigSet(_:exitConfigMode:...) async throws -> String
func telnetLogin(primaryTerminator:altTerminator:usernamePattern:passwordPattern:delay:maxLoops:) async throws -> String
func cleanup(command:) async throws
```

`promptPattern` and `supportsConfigMode` are computed properties you
can override too, if the vendor's prompt regex or config-mode support
differs from the Cisco default (`"[>#]"` / `true`).

## 4. Register the device type(s)

Netmiko's `ssh_dispatcher.py` maps `device_type` strings to classes in
a module-level dict. Swiftmiko's equivalent is
`Sources/SSHDispatcher.swift`'s `SSHDispatcher.defaultConnectionFactories`:

```swift
"arista_eos": { AristaSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
```

If the vendor supports SCP, also add an entry to
`defaultFileTransferFactories`. Add the corresponding `deviceType`
string(s) — SSH, Telnet, and SCP as applicable — to
[`PLATFORMS.md`](./PLATFORMS.md)'s `deviceType` tables, and add the
platform itself to the relevant vendor-family table with status ⬜.

A vendor can also be registered without editing `SSHDispatcher.swift`
at all, by calling `DispatcherRegistry.shared.registerConnection(_:factory:)`
at runtime — useful for a driver living outside this package.

## 5. Write a test

Add a test under `Tests/SwiftmikoTests/` using `BufferedChannel`
(`Sources/Channel.swift`) to fake the device side without a real
connection:

```swift
import XCTest
@testable import Swiftmiko

final class AristaTests: XCTestCase {
    func testSendCommandStripsEchoAndPrompt() async throws {
        let channel = BufferedChannel()
        try await channel.open()

        let profile = ConnectionProfile(
            host: "203.0.113.1", deviceType: "arista_eos",
            username: "netadmin", auth: .none
        )
        let connection = AristaSSH(profile: profile, channel: channel)
        connection.basePrompt = "switch#"

        channel.enqueueOutput("show version\nEOS Version 1.0\nswitch#")
        let output = try await connection.sendCommand("show version")

        XCTAssertEqual(output, "EOS Version 1.0")
    }
}
```

See [`TESTING.md`](./TESTING.md) for the full test-suite layout and
how to test against real/emulated hardware once you have a lab
device available.

## 6. Document any translation quirks inline

If the vendor's Netmiko source has a workaround, an outdated comment,
or a bug that's intentionally preserved rather than fixed, say so in
a short comment on the override, referencing the Netmiko source file
it came from. That's what lets a future pass distinguish "quirk we
kept on purpose" from "bug we introduced."
