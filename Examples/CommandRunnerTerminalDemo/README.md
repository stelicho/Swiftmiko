# CommandRunnerTerminalDemo

The terminal sibling of [`CommandRunnerDemo`](../CommandRunnerDemo)
(SwiftUI) and [`CommandRunnerWebDemo`](../CommandRunnerWebDemo)
(Vapor) — same idea, connect to a device over SSH and run commands
interactively, but from a plain terminal prompt. No SwiftUI, no web
framework: just `Foundation` and `Swiftmiko` itself.

That minimalism is the point. Unlike the other two, this one builds
and runs on **macOS, Linux, and Windows** — anywhere Swiftmiko's core
library does. It exists specifically to prove that, not just to be a
third UI for the same demo.

Like `CommandRunnerWebDemo`, this isn't an Xcode project — it's a
standalone Swift package with its own executable, run from the
terminal.

## Running it

```bash
cd Examples/CommandRunnerTerminalDemo
swift run
```

The first run resolves and builds Swiftmiko and its dependencies from
scratch, which takes a while (a minute or so); subsequent runs are
fast. Then just follow the prompts:

```
Swiftmiko CommandRunner — terminal edition
(macOS, Linux, or Windows — no SwiftUI, no web server)

Host: 192.168.1.1
Device type [cisco_ios]:
Username: admin
Password:
Enable secret (optional, Enter to skip):
Allow legacy AES-CBC ciphers? Only for old gear you control [y/N]:

Connecting to 192.168.1.1...
Connected.

Type a command to run it, or 'exit'/'quit' to disconnect.

192.168.1.1> show version
...
192.168.1.1> exit
Disconnected.
```

Password and enable-secret prompts don't echo to the terminal.
Leaving "Device type" blank defaults to `cisco_ios` — type any
registered `device_type` string instead (`arista_eos`, `linux`,
`juniper_junos`, `ubiquiti_unifiswitch`, ... — see `PLATFORMS.md` at
the repo root for the full list) to target something else.

If the device type doesn't support enable mode at all (Juniper,
Fortinet, VyOS/EdgeRouter, ...), entering an enable secret just prints
a warning and continues — this demo doesn't know ahead of time which
`device_type` strings do and don't support it, unlike
[`MultiVendorDemo`](../MultiVendorDemo) and
[`UbiquitiDemo`](../UbiquitiDemo), which hardcode that per platform.

## How it's structured

Everything lives in one file,
`Sources/CommandRunnerTerminalDemo/main.swift` — there's no SwiftUI
view hierarchy or Vapor routing to split across files, just: prompt
for connection details, call `SSHDispatcher.connectHandler`, then loop
reading commands until `exit`/`quit`.

The no-echo password prompt is a small, self-contained copy of
`Sources/CLITools/CommonOptions.swift`'s `promptSecure()` (termios on
Darwin/Glibc, the Win32 console API on Windows) — duplicated rather
than imported, since that function is internal to the `SwiftmikoCLI`
module and this demo deliberately depends on nothing but `Swiftmiko`
itself.

## Known limitations (it's a demo)

- **No command history, no line editing beyond whatever the terminal
  itself provides.** `readLine()` is about as basic as terminal input
  gets — no arrow-key history, no tab completion.
- **Build-verified on macOS, Linux, and Windows via CI**
  (`.github/workflows/ci.yml` builds this package in all three jobs,
  not just the main `Swiftmiko` target) — but that only proves it
  compiles everywhere, not that an actual SSH session behaves
  identically on all three; nobody's run this interactively against a
  real device on anything but macOS yet.
- **One connection at a time, no scripting mode.** For automating
  against many devices or non-interactive use, see `Examples/CLIToolsDemo`
  (`swiftmiko-show`/`cfg`/`grep`) instead — those are built for
  exactly that.
