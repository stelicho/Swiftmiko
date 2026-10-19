// Tests/SwiftmikoTests/ScriptedChannel.swift
//
// A test Channel that returns one scripted response per readAvailable()
// call, in order — unlike BufferedChannel (which returns everything
// queued so far and drains in one shot), this lets a test simulate a
// real multi-step conversation (e.g. enterEnableMode()'s own sequence
// of distinct reads) without timing-sensitive background injection.
// Each real `readChannel()` call inside BaseConnection corresponds to
// exactly one call to readAvailable() here, so the response list must
// line up 1:1 with however many times the driver under test actually
// reads the channel.

@testable import Swiftmiko

final class ScriptedChannel: Channel, @unchecked Sendable {
    private(set) var isOpen = false
    private(set) var writes: [String] = []
    private var responses: [String]
    private var responseIndex = 0
    var authenticationError: Error?

    init(responses: [String]) {
        self.responses = responses
    }

    func open() async throws {
        isOpen = true
    }

    func authenticate(username: String, using method: AuthMethod) async throws {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        if let authenticationError { throw authenticationError }
    }

    func write(_ data: String) async throws {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        writes.append(data)
    }

    func readAvailable() async throws -> String {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        guard responseIndex < responses.count else { return "" }
        defer { responseIndex += 1 }
        return responses[responseIndex]
    }

    func close() async {
        isOpen = false
    }
}
