# Swiftmiko Encryption Handling

This document describes the encryption Swiftmiko's CLI tools
(`swiftmiko-show`, `swiftmiko-cfg`, `swiftmiko-grep`,
`swiftmiko-encrypt`, `swiftmiko-bulk-encrypt` — see
`Sources/CLITools/`) use to keep passwords and enable secrets out of
plaintext in a `.swiftmiko.yml` inventory file. It's a wire-compatible
Swift port of Netmiko Tools' own `encryption_handling.py` — a file
encrypted by one tool decrypts cleanly in the other.

## Overview

`.swiftmiko.yml` is Swiftmiko's equivalent of Netmiko's
`~/.netmiko.yml` — an inventory of devices and groups
(`Sources/CLITools/DeviceInventory.swift`) that the CLI tools read by
default. Fields prefixed `__encrypt__` in that file are transparently
decrypted before use.

## Current status: both `fernet` and `aes128`, wire-compatible

```swift
enum EncryptionType: String { case fernet, aes128 }
```

`encryptValue`/`decryptValue` (`Sources/CLITools/CLIEncryption.swift`)
implement both cases to match Netmiko's own `encryption_handling.py`
byte-for-byte:

1. A random 16-byte salt plus the configured key are run through
   PBKDF2-HMAC-SHA256, 100,000 rounds, to derive a 32-byte key —
   identical parameters to Python's `cryptography` package. (The
   round count is below `_CryptoExtras`'s "safe" PBKDF2 minimum of
   210,000; matching Netmiko requires the explicit
   `unsafeUncheckedRounds` escape hatch, which is safe here since it
   exists for interop with an already-fixed wire format, not new
   crypto design.)
2. **`fernet`** splits the derived key into a 16-byte signing key and
   a 16-byte encryption key and builds a standard Fernet token
   (version byte + timestamp + IV + AES-128-CBC/PKCS7 ciphertext +
   HMAC-SHA256), exactly as Python's `cryptography.fernet.Fernet`
   does.
3. **`aes128`** uses the first 16 bytes of the derived key directly
   with AES-128-CBC/PKCS7 and a random IV — this is genuinely AES-CBC
   now, not AES-GCM (an earlier non-wire-compatible implementation
   used GCM; that has been replaced).
4. Both are stored the same way: `__encrypt__<base64 salt>:<base64
   payload>`.

A `.swiftmiko.yml` (or `.netmiko.yml`) encrypted by real Netmiko
decrypts correctly with Swiftmiko's tools, and vice versa, for either
encryption type.

## Configuration

### Basic setup

Encryption is configured in `.swiftmiko.yml` under `__meta__`, same
shape as Netmiko:

```yaml
__meta__:
  encryption: true
  encryption_type: fernet   # or aes128
```

### Encryption key

The key comes from the `SWIFTMIKO_TOOLS_KEY` environment variable and
can be any length — it's a PBKDF2 passphrase, not used as a raw AES
key directly.

```bash
export SWIFTMIKO_TOOLS_KEY="my passphrase"
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
  password: __encrypt__<base64 salt>:<base64 ciphertext>
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
swiftmiko-encrypt "my_secure_password" --type fernet
# Encrypted data: __encrypt__<base64 salt>:<base64 ciphertext>
```

Omit `--key` to read `SWIFTMIKO_TOOLS_KEY`; omit `--type` to read
`encryption_type` from `.swiftmiko.yml`'s `__meta__` section. Omit
the data argument entirely and `swiftmiko-encrypt` prompts for it
without echoing to the terminal.

### Encrypting an entire inventory file at once

```bash
swiftmiko-bulk-encrypt --input-file ~/.swiftmiko.yml --output-file ~/.swiftmiko.encrypted.yml --encryption-type fernet
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
let encrypted = try encryptValue("my_secure_password", key: key, type: "fernet")
let decrypted = try decryptValue(encrypted, key: key, type: "fernet")
```

These functions live in `SwiftmikoCLI`, not the core `Swiftmiko`
library target — they're CLI-tool internals, not part of the public
connection API.

## Security considerations

1. Store `SWIFTMIKO_TOOLS_KEY` securely and never commit it to version
   control.
2. A value's `__encrypt__` prefix is a marker for the CLI tools, not
   protection on its own; treat any `.swiftmiko.yml` file, encrypted
   or not, as sensitive.
3. Fernet's own token format embeds a timestamp but Swiftmiko (like
   Netmiko) never checks it on decrypt — there's no built-in
   expiration for encrypted inventory values.
