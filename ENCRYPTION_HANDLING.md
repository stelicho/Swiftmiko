# Swiftmiko Encryption Handling

This document describes the encryption Swiftmiko's CLI tools
(`swiftmiko-show`, `swiftmiko-cfg`, `swiftmiko-grep`,
`swiftmiko-encrypt`, `swiftmiko-bulk-encrypt` — see
`Sources/CLITools/`) use to keep passwords and enable secrets out of
plaintext in a `.swiftmiko.yml` inventory file. It's a Swift port of
Netmiko Tools' own `encryption_handling.py`, with one real
difference: **only AES-128 is implemented.**

## Overview

`.swiftmiko.yml` is Swiftmiko's equivalent of Netmiko's
`~/.netmiko.yml` — an inventory of devices and groups
(`Sources/CLITools/DeviceInventory.swift`) that the CLI tools read by
default. Fields prefixed `__encrypt__` in that file are transparently
decrypted before use.

## Current status: AES-128 only

```swift
enum EncryptionType: String { case fernet, aes128 }
```

`encryptValue`/`decryptValue` (`Sources/CLITools/CLIEncryption.swift`)
support both cases in the enum, but `.fernet` always throws
`SwiftmikoEncryptionError.fernetNotImplemented`. Use `aes128`
everywhere `.swiftmiko.yml` or the CLI tools ask for an encryption
type. AES-128 here means AES-GCM (via `swift-crypto`'s
`AES.GCM.seal`/`AES.GCM.open`), **not** the same construction
Netmiko's own `aes128` mode uses — a `.swiftmiko.yml` encrypted by
Netmiko's tools will not decrypt with Swiftmiko's, and vice versa.

## Configuration

### Basic setup

Encryption is configured in `.swiftmiko.yml` under `__meta__`, same
shape as Netmiko:

```yaml
__meta__:
  encryption: true
  encryption_type: aes128   # 'fernet' is accepted here but will fail at decrypt time
```

### Encryption key

The key comes from the `SWIFTMIKO_TOOLS_KEY` environment variable.
For AES-128, it must decode to exactly 16 bytes.

```bash
export SWIFTMIKO_TOOLS_KEY="0123456789abcdef"   # exactly 16 bytes for aes128
```

`--key` on `swiftmiko-encrypt` overrides the environment variable for
a single invocation.

## Using encryption

### Encrypted values in YAML

```yaml
arista1:
  device_type: arista_eos
  host: arista1.domain.com
  username: pyclass
  password: __encrypt__<base64-encoded-AES-GCM-ciphertext>
```

`decryptConfig` (`Sources/CLITools/CLIEncryption.swift`) walks every
device entry in a loaded `.swiftmiko.yml` and decrypts its `password`
and `secret` fields when `__meta__.encryption` is `true`.
`obtainDevices` (`Sources/CLITools/DeviceInventory.swift`) calls this
automatically, so `swiftmiko-show`/`swiftmiko-cfg`/`swiftmiko-grep`
need nothing extra beyond a correctly configured `__meta__` block and
`SWIFTMIKO_TOOLS_KEY` in the environment.

### Encrypting values from the command line

```bash
swiftmiko-encrypt "my_secure_password" --type aes128
# Encrypted data: <base64 ciphertext>
```

Omit `--key` to read `SWIFTMIKO_TOOLS_KEY`; omit `--type` to read
`encryption_type` from `.swiftmiko.yml`'s `__meta__` section. Omit
the data argument entirely and `swiftmiko-encrypt` prompts for it
without echoing to the terminal.

### Encrypting an entire inventory file at once

```bash
swiftmiko-bulk-encrypt --input-file ~/.swiftmiko.yml --output-file ~/.swiftmiko.encrypted.yml --encryption-type aes128
```

`swiftmiko-bulk-encrypt` (`Sources/CLITools/SwiftmikoBulkEncrypt.swift`)
rewrites every `password`/`secret` field it finds. Unlike Netmiko
Tools' equivalent (which uses `ruamel.yaml` to preserve comments, key
order, and quoting), Swiftmiko uses `Yams`, which reformats the whole
file — expect the output file's layout to differ from the input even
where values didn't change.

### Calling the encryption functions directly

```swift
import Foundation

let key = try getEncryptionKey()   // reads SWIFTMIKO_TOOLS_KEY
let encrypted = try encryptValue("my_secure_password", key: key, type: "aes128")
let decrypted = try decryptValue(encrypted, key: key, type: "aes128")
```

These functions live in `SwiftmikoCLI`, not the core `Swiftmiko`
library target — they're CLI-tool internals, not part of the public
connection API.

## Security considerations

1. Store `SWIFTMIKO_TOOLS_KEY` securely and never commit it to version
   control.
2. Use `aes128` — `fernet` is not implemented and will throw.
3. A value's `__encrypt__` prefix is a marker for the CLI tools, not
   protection on its own; treat any `.swiftmiko.yml` file, encrypted
   or not, as sensitive.
