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
//  Examples/CommandRunnerWebDemo/routes.swift
//
//  Three POST actions (connect / run / disconnect) mirroring the
//  SwiftUI CommandRunnerViewModel's three methods, each followed by a
//  redirect back to GET / — the standard "redirect after POST" web
//  pattern, so reloading the page never resubmits a form.
//
//  This is a demo, not a hardened production app: there's no CSRF
//  protection, no rate limiting, and no TLS termination configured.
//  Don't expose this beyond localhost without adding those.

import Vapor
import Swiftmiko

// MARK: - Form payloads

struct ConnectForm: Content {
    var host: String
    var username: String
    var password: String
    var secret: String
    // HTML checkboxes omit the field entirely when unchecked — there's
    // no "false" value on the wire, just presence or absence.
    var allowLegacyCiphers: String?
}

struct RunCommandForm: Content {
    var commandIndex: Int
    var customCommand: String
}

// MARK: - Template context

struct CommandOption: Encodable {
    var index: Int
    var label: String
}

struct IndexContext: Encodable {
    var isConnected: Bool
    var connectedHost: String?
    var commands: [CommandOption]
    var output: String
    var errorMessage: String?
}

// MARK: - Routes

func routes(_ app: Application) throws {
    app.get { req async throws -> View in
        let key = req.demoSessionKey()
        let state = await SessionStore.shared.state(for: key)
        return try await req.view.render("index", IndexContext(
            isConnected: state.connection != nil,
            connectedHost: state.connectedHost,
            commands: CommonCommand.library.enumerated().map {
                CommandOption(index: $0.offset, label: $0.element.label)
            },
            output: state.lastOutput,
            errorMessage: state.errorMessage
        ))
    }

    app.post("connect") { req async throws -> Response in
        let key = req.demoSessionKey()
        let form = try req.content.decode(ConnectForm.self)

        let profile = ConnectionProfile(
            host: form.host,
            deviceType: "cisco_ios",
            username: form.username,
            auth: .password(form.password),
            secret: form.secret.isEmpty ? nil : form.secret,
            allowLegacyCiphers: form.allowLegacyCiphers != nil
        )

        do {
            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            if !form.secret.isEmpty {
                try await connection.enterEnableMode(secret: form.secret)
            }
            await SessionStore.shared.update(for: key) { state in
                state.connection = connection
                state.connectedHost = form.host
                state.errorMessage = nil
                state.lastOutput = ""
            }
        } catch {
            await SessionStore.shared.update(for: key) { state in
                state.connection = nil
                state.connectedHost = nil
                state.errorMessage = error.localizedDescription
            }
        }
        return req.redirect(to: "/")
    }

    app.post("run") { req async throws -> Response in
        let key = req.demoSessionKey()
        let form = try req.content.decode(RunCommandForm.self)
        let state = await SessionStore.shared.state(for: key)

        guard let connection = state.connection else {
            await SessionStore.shared.update(for: key) { state in
                state.errorMessage = "Not connected — press Connect first."
            }
            return req.redirect(to: "/")
        }

        let trimmedCustom = form.customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = trimmedCustom.isEmpty
            ? CommonCommand.library[safe: form.commandIndex]?.command
            : trimmedCustom

        guard let command, !command.isEmpty else {
            await SessionStore.shared.update(for: key) { state in
                state.errorMessage = "No command selected."
            }
            return req.redirect(to: "/")
        }

        do {
            let output = try await connection.sendCommand(command, readTimeout: 30.0)
            await SessionStore.shared.update(for: key) { state in
                state.lastOutput = output
                state.errorMessage = nil
            }
        } catch {
            await SessionStore.shared.update(for: key) { state in
                state.errorMessage = error.localizedDescription
            }
        }
        return req.redirect(to: "/")
    }

    app.post("disconnect") { req async throws -> Response in
        let key = req.demoSessionKey()
        let state = await SessionStore.shared.state(for: key)
        await state.connection?.disconnect()
        await SessionStore.shared.clear(for: key)
        return req.redirect(to: "/")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
