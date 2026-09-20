# Common Issues

Swiftmiko-specific gotchas, translated and expanded from Netmiko's
own `COMMON_ISSUES.md`. See [`EXAMPLES.md`](./EXAMPLES.md) for the
full code for anything referenced here only briefly.

### Show commands that prompt for more information

For a command that prompts mid-execution, use `sendCommandTiming` —
it's purely delay-based and doesn't wait for a prompt match, so it
won't hang if the device's response doesn't look like a normal
prompt.

```
pynet-rtr1#copy running-config flash:test1.txt
Destination filename [test1.txt]?
5587 bytes copied in 1.316 secs (4245 bytes/sec)

pynet-rtr1#
```

```swift
var output = try await connection.sendCommandTiming(
    "copy running-config flash:test1.txt"
)
if output.contains("Destination filename") {
    output += try await connection.sendCommandTiming("\n")
}
print(output)
```

### Logging all reads and writes of the communications channel

Construct the driver directly (rather than through
`SSHDispatcher.connectHandler`, which doesn't expose this) and pass a
`SessionLogConfig`:

```swift
let connection = CiscoIOSSSH(
    profile: profile,
    sessionLog: SessionLogConfig(filePath: "session.log", recordWrites: true),
    channelProvider: nioSSHChannelProvider
)
```

For lower-level `TRACE`/`DEBUG` output about what the driver itself
is doing (not just what's on the wire), every `BaseConnection` also
has a `SwiftmikoLogger`, controlled by the `logLabel`/`loggerEnabled`
initializer parameters. It's deliberately minimal — there's no
`swift-log` backend wiring yet, just `print()` — so don't expect
Netmiko's `logging.basicConfig()`-style configurability.

### Does Swiftmiko support connecting via a terminal server?

Yes. `TerminalServer`/`TerminalServerSSH`/`TerminalServerTelnet`
(`Sources/TerminalServer/TerminalServer.swift`) skip session
preparation entirely, so you can connect and then drive
`writeChannel`/`readChannel`/`telnetLogin` by hand to get through the
terminal server to whatever's on the other side — same idea as
Netmiko's `terminal_server` device type. From there,
`SSHDispatcher.redispatch(_:deviceType:sessionPreparation:)`
transplants the existing, already-authenticated channel onto a new
driver instance for the real device you've reached, without
reconnecting — see [Terminal server and redispatch](./EXAMPLES.md#terminal-server-and-redispatch)
for the full worked example (switch → terminal server → end device,
two hops, two redispatches).

### Most `deviceType` strings from `PLATFORMS.md` connect out of the box

`SSHDispatcher.defaultConnectionFactories` (`Sources/SSHDispatcher.swift`)
registers essentially every vendor driver ported under `Sources/`. A
small number of `deviceType` strings that exist in Netmiko have no
Swift driver ported yet (e.g. `huawei_olt`, `fiberstore_fsosv2`,
`brocade_vyos`) and are intentionally left unregistered rather than
pointed at a guessed-at substitute — check `PLATFORMS.md`'s status
column, or `SSHDispatcher.platforms`, if a `deviceType` you expect
doesn't resolve. `DispatcherRegistry.shared.registerConnection` lets
you add (or override) an entry at runtime without touching
`SSHDispatcher.swift`:

```swift
await DispatcherRegistry.shared.registerConnection("some_new_device") {
    SomeDriverSSH(profile: $0, channelProvider: nioSSHChannelProvider)
}
```

### Connecting to an old device fails with "Unexpected message type has arrived"

Older SSH servers (e.g. classic Cisco C7200 IOS images) may not
offer AES-GCM ciphers, and negotiation can succeed on cipher/KEX/host
key while the actual encrypted traffic still fails. Opt in to the
legacy AES-CBC fallback on the profile if you control the device and
accept the weaker cipher:

```swift
var profile = ConnectionProfile(/* ... */)
profile.allowLegacyCiphers = true
```

This is implemented via a `CommonCrypto`-backed AES-CBC shim (see
`Sources/CCommonCryptoShim/` and
`Tests/SwiftmikoTests/LegacyCBCTransportProtectionTests.swift`) and
defaults to `false` — leave it off for anything but lab/EOL gear you
control.

### Encryption: Fernet isn't implemented

`.swiftmiko.yml`'s `__meta__.encryption_type` accepts `fernet`, but
using it throws at encrypt/decrypt time. Use `aes128`. See
[`ENCRYPTION_HANDLING.md`](./ENCRYPTION_HANDLING.md).

### No TextFSM, Genie, or TTP

`sendCommand`/`sendCommandTiming` always return a plain `String`.
There's no structured-output parsing layer ported from Netmiko yet —
parse the raw text yourself.

### Building from source

Swiftmiko depends on a local fork of `swift-nio-ssh`
(`Sources/swift-nio-ssh` — see the comment in `Package.swift`) that
adds classic Diffie-Hellman group14-sha1 key exchange for SSH servers
too old to offer ECDH/Curve25519. If `swift build` can't resolve
dependencies, make sure that path exists rather than trying to fetch
`swift-nio-ssh` from GitHub directly.

### Installing the CLI tools

The CLI tools (`swiftmiko-show`, `swiftmiko-cfg`, `swiftmiko-grep`,
`swiftmiko-encrypt`, `swiftmiko-bulk-encrypt`) are ordinary SwiftPM
executable products, not something installed separately:

```bash
swift build -c release
.build/release/swiftmiko-show my-device --cmd "show version"
```

There's no Poetry/virtualenv equivalent to install here — it's the
same `swift build`/`swift test` toolchain as the library itself. See
[`CONTRIBUTING.md`](./CONTRIBUTING.md).
