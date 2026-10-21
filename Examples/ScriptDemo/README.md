# ScriptDemo

Proof that Swiftmiko scripts the way Netmiko does: a plain
command-line program, no SwiftUI, no Xcode project, no YAML inventory
file to set up first — just connection details and a command as flags,
exactly the way a typical Netmiko quickstart script hardcodes a device
dict and calls `send_command()`.

Like [`CommandRunnerTerminalDemo`](../CommandRunnerTerminalDemo), this
isn't an Xcode project — it's a standalone Swift package with its own
executable, and it builds and runs on **macOS, Linux, and Windows**,
anywhere Swiftmiko's core library does. Unlike that demo, this one
isn't interactive: it takes everything it needs as command-line
arguments, runs exactly one command, prints the output, and exits —
closer to a script you'd drop into a cron job or a CI pipeline than a
REPL you sit and type into.

It targets Cisco IOS specifically (`deviceType` is hardcoded, not a
flag) — for a flag/picker across multiple vendors, see
[`MultiVendorDemo`](../MultiVendorDemo). For running the same command
across a whole fleet from a YAML inventory file instead of one
device's connection details by hand, see
[`CLIToolsDemo`](../CLIToolsDemo) (`swiftmiko-show`).

## Running it

```bash
cd Examples/ScriptDemo
swift run ScriptDemo --host 192.168.1.1 --username admin --command "show version"
```

The first run resolves and builds Swiftmiko, ArgumentParser, and their
dependencies from scratch, which takes a while (a minute or so);
subsequent runs are fast.

```
Password:
Connecting to 192.168.1.1...
Connected. Running: show version
Cisco IOS Software, ...
Disconnected.
```

Omit `--password` to be prompted for it securely (no echo to the
terminal) instead of passing it on the command line, where it'd be
visible in shell history and `ps`/process-list output. Add
`--allow-legacy-ciphers` for old IOS images that predate AES-GCM —
only against lab/EOL gear you control, see `SECURITY.md` at the repo
root for why this is opt-in. `--command` defaults to `"show version"`
if omitted.

```bash
swift run ScriptDemo --help
```

shows the full flag list.

## How it's structured

Two files under `Sources/ScriptDemo/`: `ScriptDemo.swift` (the
`AsyncParsableCommand` itself — flags, connect, run one command,
disconnect) and a one-line `main.swift` that just calls
`ScriptDemo.runAsMain()`. That split (rather than `@main` directly on
the command struct) sidesteps a real ambiguity in how Swift resolves
`AsyncParsableCommand`'s `main()` — see the comment on `runAsMain()`
in `ScriptDemo.swift`, and the identical pattern already used by
`Sources/CLITools/SwiftmikoShow.swift`.

The no-echo password prompt is a small, self-contained copy of
`Sources/CLITools/CommonOptions.swift`'s `promptSecure()` — duplicated
rather than imported, since that function is internal to the
`SwiftmikoCLI` module and this demo deliberately depends on nothing
but `Foundation`, `ArgumentParser`, and `Swiftmiko` itself.

## Known limitations (it's a demo)

- **One command per run, one device per run.** For looping over
  multiple devices or commands without re-invoking the binary each
  time, see `CommandRunnerTerminalDemo` (interactive) or
  `CLIToolsDemo` (inventory-file-driven, built for exactly this).
- **Cisco IOS only.** `deviceType` is hardcoded rather than a flag —
  intentionally, to keep this example's surface small. Swap the
  hardcoded `"cisco_ios"` in `ScriptDemo.swift` for any other
  registered `device_type` string (see `PLATFORMS.md`) to point it
  elsewhere.
- **Verified to build and attempt a real connection in this
  environment** (confirmed via `swift build` and a direct run against
  an unreachable test address, which produced a genuine SSH connection
  attempt and timeout) — but nobody has run this against an actual
  Cisco IOS device yet.
