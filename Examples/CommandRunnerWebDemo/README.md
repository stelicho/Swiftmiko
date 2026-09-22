# CommandRunnerWebDemo

A browser-based sibling of [`CommandRunnerDemo`](../CommandRunnerDemo) —
same idea (connect to a Cisco IOS device over SSH, run a show command,
see the output), served over HTTP with [Vapor](https://vapor.codes)
and [Leaf](https://github.com/vapor/leaf) instead of a native SwiftUI
window.

Unlike every other project under `Examples/`, this one isn't an Xcode
project — it's a standalone Swift package with its own executable, run
from the terminal.

## Why a web app can do this at all

Swiftmiko needs a real TCP socket to speak SSH — that only works
server-side. This is **not** a SwiftWasm/client-side app; it's an
ordinary server-side Swift process (the kind you'd deploy to a Linux
box, if Swiftmiko itself were Linux-portable — see "Known
limitations" below) that happens to render its UI as HTML instead of
JSON.

## Running it

```bash
cd Examples/CommandRunnerWebDemo
swift run
```

Then open <http://localhost:8080>. Everything else is the same
workflow as the native demo: fill in a host/username/password
(and an enable secret if you need one), hit **Connect**, pick a
command (or type your own), hit **Run**.

## How it's structured

- `Sources/CommandRunnerWebDemo/entrypoint.swift` / `configure.swift`
  / `routes.swift` — standard Vapor app skeleton.
- `SessionStore.swift` — HTTP is stateless; a live SSH connection
  isn't. The session cookie carries only an opaque ID; this in-memory
  actor maps that ID to the actual `BaseConnection` and the bits of
  UI state (last output, last error) that need to survive the
  redirect-after-POST round trip back to `GET /`.
- `routes.swift` — three `POST` actions (`/connect`, `/run`,
  `/disconnect`) mirroring `CommandRunnerViewModel`'s three methods
  from the SwiftUI version, each followed by a redirect back to `/`
  (the standard "redirect after POST" pattern, so reloading the page
  never resubmits a form).
- `Resources/Views/index.leaf` — the entire UI, one server-rendered
  page, no JavaScript.

## Known limitations (it's a demo)

- **No CSRF protection, no rate limiting, no TLS.** Don't expose this
  beyond `localhost` without adding those.
- **No guard against double-submission.** There's no JavaScript
  disabling the Run button while a command is in flight, so two quick
  clicks (or two browser tabs sharing one session cookie) could call
  methods on the same `BaseConnection` concurrently — which it isn't
  designed for. The native SwiftUI demo avoids this via
  `isRunning`-gated buttons; this one doesn't have an equivalent guard
  yet.
- **macOS-only, same as the rest of Swiftmiko.** The core library
  links Apple's CommonCrypto for its legacy-cipher fallback and isn't
  Linux-portable today, so this can't actually be deployed to a Linux
  server despite being an otherwise-ordinary Vapor app. Run it
  locally via `swift run`.
