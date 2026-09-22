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
//  Examples/CommandRunnerWebDemo/configure.swift

import Vapor
import Leaf

func configure(_ app: Application) async throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Cookie-based sessions. The connection itself can't live inside the
    // session (BaseConnection isn't Codable, and shouldn't be — it owns
    // a live socket), so the session cookie only carries an opaque ID;
    // SessionStore below maps that ID to the actual server-side state.
    app.middleware.use(app.sessions.middleware)

    app.views.use(.leaf)

    try routes(app)
}
