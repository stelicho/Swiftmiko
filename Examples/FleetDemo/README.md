# FleetDemo

Runs one command against several devices **at once**, not one at a
time — the visible, SwiftUI counterpart to what `swiftmiko-show`/
`swiftmiko-cfg`/`swiftmiko-grep` already do under the hood
(`Sources/CLITools/SSHConn.swift`'s `runDeviceTasks`), built on the
same idea: fan out via `withTaskGroup`, fan back in as each connection
finishes.

## How it's structured

Each device row is just a `host` + `deviceType` pair — credentials and
the command to run are shared across the whole fleet, kept in
`FleetViewModel`. `runFleet()` captures only plain `String`/`Bool`
values into each child task (never `self`), and each child task
*returns* its result rather than mutating shared state directly —
`results[id] = state` only ever happens back in the `for await`
loop, which resumes on the view model's own `@MainActor` isolation as
each task completes. That's what makes the UI update one device at a
time as results land, rather than all at once at the end: a fast
device's checkmark appears before a slow one's spinner even finishes.

## Running it

Fill in a few hosts (leave extra rows blank to skip them), set
username/password/command once, and press **Run Fleet**. Each row
gets its own status icon — pending, spinning while in flight, a green
check with the command's output once it succeeds, or a red X with the
error message if that one device failed. One device failing doesn't
block or slow down the others; `withTaskGroup`'s child tasks are
fully independent.

**Note:** every device here authenticates with the *same* username/
password. Real fleets often have per-device credentials — this demo
keeps it simple on purpose; wiring in per-row credentials would just
mean adding `username`/`password` fields to `FleetDevice` instead of
`FleetViewModel`.
