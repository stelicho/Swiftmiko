# CLIToolsDemo

A walkthrough of Swiftmiko's five command-line tools — `swiftmiko-show`,
`swiftmiko-cfg`, `swiftmiko-grep`, `swiftmiko-encrypt`, and
`swiftmiko-bulk-encrypt` — Swift ports of Netmiko Tools'
`netmiko-show`/`netmiko-cfg`/`netmiko-grep`/`netmiko-encrypt`/
`netmiko-bulk-encrypt`.

Unlike everything else under `Examples/`, this isn't a SwiftUI app at
all (not even a standalone one like
[`CommandRunnerWebDemo`](../CommandRunnerWebDemo)) — the tools already
exist as executables in the main `Swiftmiko` package
(`Sources/CLITools/`); this directory is just a sample inventory file
plus the walkthrough below. There's no code to run here beyond the
tools themselves.

Every command and its output in this README was actually run while
writing it (`--version`, `--list-devices`, `swiftmiko-encrypt`,
`swiftmiko-bulk-encrypt`) — the `swiftmiko-show`/`cfg`/`grep` examples
against `router1`/`switch1`/`linux1` are illustrative, since those
hosts are placeholders. Swap them for a real device — any of the
other `Examples/` apps in this repo already point at one.

## Building the tools

From the repository root:

```bash
swift build -c release
```

This builds every target in `Package.swift`, including the five CLI
tools, into `.build/release/`. For faster iteration while trying
things out, `swift run <tool-name> ...` works too (slower to start,
since it rebuilds on every invocation if anything changed).

```bash
swift build -c release \
  --product swiftmiko-show --product swiftmiko-cfg --product swiftmiko-grep \
  --product swiftmiko-encrypt --product swiftmiko-bulk-encrypt
```

builds just these five, if you don't want the rest of the package's
executables.

## The inventory file

All three of `swiftmiko-show`/`cfg`/`grep` read a `.swiftmiko.yml`
inventory — Swiftmiko's equivalent of Netmiko's `~/.netmiko.yml` — by
default from `~/.swiftmiko.yml`, or from the path in the
`SWIFTMIKO_TOOLS_CFG` environment variable. [`sample.swiftmiko.yml`](./sample.swiftmiko.yml)
in this directory is a working example:

```yaml
router1:
  device_type: cisco_ios
  host: 192.168.1.10
  username: admin
  password: changeme
  secret: enablepass

switch1:
  device_type: arista_eos
  host: 192.168.1.20
  username: admin
  password: changeme

lab_devices:
  - router1
  - switch1
```

Top-level keys are either a device (a mapping with `device_type`,
`host`, `username`, and optionally `password`/`secret`/`port`) or a
group (a plain list of device names). `all` always means every device
in the file, whether or not a group literally named `all` exists.

Point the tools at it for this walkthrough:

```bash
export SWIFTMIKO_TOOLS_CFG="$(pwd)/Examples/CLIToolsDemo/sample.swiftmiko.yml"
```

(Or copy it to `~/.swiftmiko.yml` and skip the environment variable
entirely — that's the default path every tool falls back to.)

```console
$ swiftmiko-show --list-devices
lab_devices: router1, switch1, linux1
linux1
router1
switch1
```

## swiftmiko-show

Runs a command — `show run` by default, or whatever
`Sources/CLITools/SwiftmikoShow.swift`'s `showRunMapper` maps the
device's `device_type` to — against a device or group, printed in a
bordered panel per device.

```bash
swiftmiko-show router1
swiftmiko-show lab_devices --cmd "show version"
swiftmiko-show all --json
```

```console
$ swiftmiko-show --version
swiftmiko-show v0.1.0
```

Useful flags (shared across `show`/`cfg`/`grep` — see
`Sources/CLITools/CommonOptions.swift`):

| Flag | Effect |
|---|---|
| `--cmd "<command>"` | Override the default/mapped command |
| `--username <name>` | Override every device's inventory username for this run |
| `--password` | Prompt for a password (not echoed) to override every device's inventory password |
| `--secret` | Prompt for an enable secret to override every device's inventory secret |
| `--json` | JSON output instead of bordered-panel text |
| `--raw` | Plain output, no panels/colors; combine with `--json` for raw (non-pretty-printed) JSON |
| `--hide-empty` | Drop devices whose output was empty |
| `--hide-failed` | Suppress the "Failed devices" summary panel |
| `--display-runtime` | Print total elapsed time at the end |

`--username`/`--password`/`--secret` apply to *every* device in the
run, not per-device — there's no way to override just one device's
credentials from the command line; edit the inventory file for that.

## swiftmiko-cfg

Same device/group targeting as `swiftmiko-show`, but sends
configuration commands instead of a show command.

```bash
# A single command
swiftmiko-cfg router1 --cmd "ntp server 10.0.0.1"

# Multiple commands: a literal \n inside the --cmd string splits them
swiftmiko-cfg router1 --cmd "interface Gi0/1\nno shutdown"

# Or read them from a file, one command per line
swiftmiko-cfg router1 --infile commands.txt
```

`--cmd` takes priority if both `--cmd` and `--infile` are given.
Neither one is optional — omitting both throws "No configuration
commands provided."

## swiftmiko-grep

Runs a command (same default/mapping as `swiftmiko-show`) and prints
only the lines matching a regex pattern, with two lines of context on
either side — the closest Swiftmiko equivalent of Netmiko's `rich`-based
highlighted grep view (see "Known differences from Netmiko" below for
what's actually different about the output).

```bash
swiftmiko-grep "^interface" lab_devices
swiftmiko-grep "access-list \d+" router1 --cmd "show run"
```

The pattern is a positional argument and comes *before* the
device/group, unlike `show`/`cfg` where the device/group is the only
positional.

## Encryption: swiftmiko-encrypt and swiftmiko-bulk-encrypt

For keeping passwords and secrets out of plaintext in
`.swiftmiko.yml`. The full design (key handling, what's actually
implemented vs. not) is in [`ENCRYPTION_HANDLING.md`](../../ENCRYPTION_HANDLING.md)
at the repo root — this is the short version, with verified example
output.

**Only `aes128` works today.** `.swiftmiko.yml`'s `encryption_type:
fernet` is accepted but throws at encrypt/decrypt time — always pass
`--type aes128` / `--encryption-type aes128` explicitly, or set
`encryption_type: aes128` in `__meta__`.

The key comes from `SWIFTMIKO_TOOLS_KEY` and must be exactly 16 bytes
for AES-128 (so, for a plain ASCII string, exactly 16 characters):

```console
$ export SWIFTMIKO_TOOLS_KEY="0123456789abcdef"
$ swiftmiko-encrypt "my_secure_password" --type aes128

Encrypted data: xnirBG8z9aEXeg+hlVfFd/mljYIFSMTyjvShnfRkDPl87pLvQqzeEkwhHY84qw==
```

(Your own output will differ — AES-GCM includes a random nonce, so
encrypting the same string twice never produces the same ciphertext.
That's expected, not a bug.)

Omit the data argument and it prompts for it without echoing to the
terminal; omit `--key`/`--type` and it falls back to
`SWIFTMIKO_TOOLS_KEY`/`.swiftmiko.yml`'s `__meta__.encryption_type`.

To encrypt an entire inventory file's `password`/`secret` fields at
once:

```console
$ swiftmiko-bulk-encrypt \
    --input-file Examples/CLIToolsDemo/sample.swiftmiko.yml \
    --output-file /tmp/sample.encrypted.swiftmiko.yml \
    --encryption-type aes128
Encrypted .swiftmiko.yml file has been written to /tmp/sample.encrypted.swiftmiko.yml
```

The output file's `__meta__.encryption` is set to `true` automatically
(along with `encryption_type`, matching whatever `--encryption-type`
you passed) — even if the input had `encryption: false`, as
`sample.swiftmiko.yml` does, since it ships with plaintext passwords
for readability. Without that, `swiftmiko-show`/`cfg`/`grep` would skip
decryption entirely and hand the ciphertext straight to the device as
if it were the actual password — this used to be a real bug here
(`swiftmiko-bulk-encrypt` left `__meta__` untouched), fixed in
`Sources/CLITools/SwiftmikoBulkEncrypt.swift`.

Also worth knowing: unlike Netmiko Tools (which uses `ruamel.yaml` to
preserve comments, key order, and quoting), Swiftmiko uses `Yams`,
which reformats the whole file — don't expect the output file's layout
to resemble the input's, even for lines that didn't change.

## Known differences from Netmiko

- **Output is plainer.** Netmiko Tools renders through Python's `rich`
  library (adaptive terminal-width panels, real syntax-highlighted
  JSON, themed colors). `Sources/CLITools/Outputters.swift` reimplements
  the *shape* of that — bordered panels, colored device names,
  highlighted grep matches — using raw ANSI escape codes against a
  fixed width, not a real terminal-rendering library. Functionally
  equivalent, visually simpler.
- **`fernet` encryption isn't implemented.** Use `aes128` everywhere;
  see [`ENCRYPTION_HANDLING.md`](../../ENCRYPTION_HANDLING.md).
- **Credential overrides are all-or-nothing.** `--username`/`--password`/`--secret`
  replace that field for every device targeted in one run, not a
  single device.
- **Every run attempts enable mode first**, even for `swiftmiko-show`
  with a plain `show` command and even against `linux`/`ovs_linux`
  device types (where "enable mode" means `sudo -s` — see the comment
  on `linux1` in `sample.swiftmiko.yml`). A device that can't elevate
  (no secret configured, non-root user, no passwordless sudo) fails
  that device entirely rather than still running the show command as
  a normal user.
