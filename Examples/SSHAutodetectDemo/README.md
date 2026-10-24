# SSHAutodetectDemo

The SSH-transport sibling of [`SNMPDemo`](../SNMPDemo): connects to a
device whose type you don't already know, and asks `SSHDetect`
(`Sources/SSHAutodetect.swift`) to guess it from the device's own
banners and command output — the same per-vendor signature table real
Netmiko's `SSHDetect` uses.

## How it connects

Rather than probing with a real vendor driver (the way `EXAMPLES.md`'s
own reference snippet does, using `"cisco_ios"` as the probe type),
this demo connects as `"generic_termserver"` — `TerminalServerSSH`,
whose `sessionPreparation()` is a deliberate no-op. `SSHDetect` only
needs a live, authenticated connection to read from; it doesn't care
what driver backs it. Probing with a real vendor driver risks sending
that vendor's own setup commands (disable paging, detect a prompt
shape) at a device that isn't actually that vendor, which can hang or
behave strangely instead of just failing to match a signature.

## Running it

Enter a host, username, and password, then **Detect**. Results show
the best-guess `deviceType` plus every signature that scored above
zero, most confident first (`SSHDetect.potentialMatches`). **Verify by
connecting** closes the loop: reconnects using the detected type for
real and shows the resulting prompt, proving the guess actually works
rather than just printing a string.
