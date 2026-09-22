//
//  ┌───────────────────────────────────────────────────────┐
//  │                   S W I F T M I K O                   │
//  │  Swift-Native Multi-Vendor Network Device Automation  │
//  └───────────────────────────────────────────────────────┘
//
//  Author & Maintainer: K.K. Campbell
//  Created with the assistance of Claude Sonnet 5 (Anthropic),
//  via Claude Code.
//
//  Examples/CommandRunnerWebDemo/SessionStore.swift
//
//  HTTP is stateless; a live Swiftmiko connection is not. Vapor's
//  session cookie carries only an opaque ID (see configure.swift) —
//  this actor maps that ID to the actual BaseConnection and the bits
//  of UI state (last output, last error) that need to survive the
//  redirect-after-POST round trip back to GET /.
//
//  This is process-local, in-memory state, same as the SwiftUI demo's
//  @Observable view model holding one `connection` property — it just
//  needs to be keyed by session now that there can be more than one
//  browser tab talking to this process at once.

import Vapor
import Swiftmiko

extension Request {
    /// A stable per-browser-session key, independent of Vapor's own
    /// `Session.id` (which isn't guaranteed to exist yet on the very
    /// first request before the session middleware has persisted a
    /// cookie). Stored inside the session's own string dictionary, so
    /// it round-trips through the same cookie Vapor already manages.
    func demoSessionKey() -> String {
        if let existing = session.data["demoSessionKey"] {
            return existing
        }
        let newKey = UUID().uuidString
        session.data["demoSessionKey"] = newKey
        return newKey
    }
}

// BaseConnection isn't Sendable (it's a mutable reference type meant to
// be driven serially by one caller at a time — same story as
// BufferedChannel/SerialChannel elsewhere in Swiftmiko). Safe here
// because every access goes through the SessionStore actor below,
// which serializes reads/writes to the state itself. It does NOT by
// itself prevent two concurrent requests sharing one session cookie
// from both calling a method on the *same* connection at once — see
// the README's "known limitations" note.
struct DemoSessionState: @unchecked Sendable {
    var connection: BaseConnection?
    var connectedHost: String?
    var lastOutput: String = ""
    var errorMessage: String?
}

actor SessionStore {
    static let shared = SessionStore()

    private var states: [String: DemoSessionState] = [:]

    func state(for sessionID: String) -> DemoSessionState {
        states[sessionID] ?? DemoSessionState()
    }

    func update(
        for sessionID: String,
        _ mutate: (inout DemoSessionState) -> Void
    ) {
        var state = states[sessionID] ?? DemoSessionState()
        mutate(&state)
        states[sessionID] = state
    }

    func clear(for sessionID: String) {
        states[sessionID] = nil
    }
}
