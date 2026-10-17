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
initializer parameters. It's backed by real `swift-log` (see
`Sources/BaseConnection.swift`), so the embedding app controls
format/destination/level the normal swift-log way via
`LoggingSystem.bootstrap(_:)`; without a bootstrap call it falls back
to swift-log's own default handler, which prints to stderr.

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

### Every `deviceType` string in `PLATFORMS.md` now connects out of the box

`SSHDispatcher.defaultConnectionFactories` (`Sources/SSHDispatcher.swift`)
registers every vendor driver ported under `Sources/`, plus the
handful of Netmiko `deviceType` strings that turn out to be pure
aliases to one of those drivers rather than a distinct class:
`huawei_olt`/`huawei_olt_telnet` (alias to `HuaweiSmartAXSSH` — the
telnet variant aliases the *SSH* class too, matching a real quirk in
Netmiko's own mapping, since no dedicated SmartAX Telnet class exists
upstream either), `brocade_vyos` (alias to `VyOSSSH`), and
`cisco_s500`/`cisco_s500_telnet` (alias to `CiscoS300SSH`/
`CiscoS300Telnet`). `fiberstore_fsosv2`/`fiberstore_fsosv2_telnet`
looked like it belonged in that same bucket but is actually Netmiko's
own distinct class, so it's ported as its own Swift class
(`FiberstoreFsosV2SSH`/`FiberstoreFsosV2Telnet`) alongside the
original `FiberstoreFsosSSH`. If a `deviceType` you expect still
doesn't resolve, check `PLATFORMS.md`'s status column, or
`SSHDispatcher.platforms`. `DispatcherRegistry.shared.registerConnection`
lets you add (or override) an entry at runtime without touching
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

This is implemented via a cross-platform AES-CBC wrapper backed by
swift-crypto's `_CryptoExtras` module (see
`Sources/LegacyCBCTransportProtection.swift` and
`Tests/SwiftmikoTests/LegacyCBCTransportProtectionTests.swift`) and
defaults to `false` — leave it off for anything but lab/EOL gear you
control.

### Connecting to a 2010-era device fails immediately with "Unexpected end of file"

This is a different failure from the one above: the connection dies
right after key exchange starts, before any cipher is negotiated at
all. Devices old enough to predate `diffie-hellman-group14-sha1`
support (some mainline Cisco IOS 12.4 images from 2010 or so, for
example) only offer `diffie-hellman-group1-sha1` for key exchange —
despite the name, this is RFC 4253's "Oakley Group 2" (1024-bit MODP),
not the smaller 768-bit "Oakley Group 1" some tooling's comments
(including an earlier version of this project's) describe it as. It's
weak by modern standards, so — like the CBC cipher fallback above —
it's opt-in only, and the *same* `allowLegacyCiphers` flag covers both:

```swift
var profile = ConnectionProfile(/* ... */)
profile.allowLegacyCiphers = true
```

`ssh -vv` straight at the device (with `-oKexAlgorithms=`,
`-oHostKeyAlgorithms=`, and `-oCiphers=` overridden to include the old
algorithms) is the fastest way to confirm what a given device actually
offers before assuming this is the cause — see
`Sources/swift-nio-ssh/Sources/NIOSSH/Key Exchange/ClassicDiffieHellmanKeyExchange.swift`
for the implementation.

### TextFSM: native, works with real ntc-templates. Genie and TTP: not implemented

`sendCommand`/`sendCommandTiming` still always return a plain `String` —
structured parsing is opt-in, not automatic the way Netmiko's
`use_textfsm=True` is.

**TextFSM** (`Sources/TextFSM/`) is a full native Swift port of Google's
textfsm — not a simplified dialect, it runs real, unmodified
[ntc-templates](https://github.com/networktocode/ntc-templates) files
directly, with no Python involved:

```swift
let template = try TextFSMTemplate(
    templateString: try String(contentsOfFile: "cisco_ios_show_version.textfsm")
)
let rows = try template.parseTextToDicts(rawShowVersionOutput)
// rows: [[String: Any]] — one dict per record; List-typed values come
// back as [String] or [[String: String]], matching real textfsm's own
// mixed-type row shape.
```

Or via the existing `TextFSMParserAdapter` hook in `Utilities.swift`
(`getStructuredDataTextFSM`/`structuredDataConverter`), using
`NativeTextFSMParser()`. `platform`/`command` → template
auto-selection also works now, the same way Netmiko's `CliTable`
does it: point `NET_TEXTFSM` at an ntc-templates checkout (or
`~/ntc-templates/ntc_templates/templates`, same fallback Netmiko
uses) and omit `template:` — `TextFSMIndexTable`
(`Sources/TextFSM/TextFSMIndexTable.swift`) reads the real `index`
file unmodified, including its `[[completion]]` syntax and regex
Platform/Command columns, and resolves the template the same
first-match-wins-in-file-order way `IndexTable.GetRowMatch` does.
One real gap: a handful of index rows map one command to *several*
templates to be joined (e.g. `show module` on `cisco_ios`/`cisco_asa`)
— that join isn't implemented, so those specific rows throw a clear
error rather than silently merging or dropping data; pass an explicit
`template:` for one of them instead.

**Genie** has no generic engine to port in the first place — every
pyATS/Genie parser is its own hand-written Python class with bespoke
regex logic, not a declarative template read by a shared interpreter.
There's no realistic "native Swift Genie" short of hand-translating
thousands of individual parsers.

**TTP** is template-driven like TextFSM, so it's feasible, but with a
richer Jinja-like DSL and a smaller real-world template ecosystem than
ntc-templates — not implemented, lower priority if anyone wants to
pick it up.

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
