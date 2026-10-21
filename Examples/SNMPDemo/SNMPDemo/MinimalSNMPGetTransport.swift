// Examples/SNMPDemo/MinimalSNMPGetTransport.swift
//
// Swiftmiko ships SNMPDetect's device-autodetection *logic* (matching
// a sysDescr-style response against known patterns) but deliberately
// leaves the actual SNMP wire client up to the caller via the
// `SNMPTransport` protocol — there's no bundled GET/WALK implementation
// to depend on. This is a minimal, real (not mocked) SNMP v1/v2c
// GET-only transport over UDP, written for this demo.

import Foundation
import Network
import Swiftmiko

final class MinimalSNMPGetTransport: SNMPTransport {
    enum TransportError: Error, LocalizedError {
        case unsupportedVersion
        case communityRequired
        case timedOut
        case connectionFailed(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "This demo transport only supports SNMP v1/v2c (not v3)."
            case .communityRequired:
                return "An SNMP community string is required for v1/v2c."
            case .timedOut:
                return "Timed out waiting for an SNMP response."
            case .connectionFailed(let reason):
                return "SNMP connection failed: \(reason)"
            case .emptyResponse:
                return "The SNMP agent closed the connection without responding."
            }
        }
    }

    var timeout: TimeInterval = 5.0

    func get(
        hostname: String,
        port: Int,
        oid: String,
        credentials: SNMPCredentials
    ) async throws -> String? {
        guard credentials.version == .v1 || credentials.version == .v2c else {
            throw TransportError.unsupportedVersion
        }
        guard let community = credentials.community, !community.isEmpty else {
            throw TransportError.communityRequired
        }

        let requestID = Int32.random(in: 0...Int32.max)
        let request = try SNMPBEREncoder.encodeGetRequest(
            version: credentials.version == .v1 ? 0 : 1,
            community: community,
            requestID: requestID,
            oid: oid
        )

        let response = try await send(request, to: hostname, port: port)
        return try SNMPBERDecoder.decodeVarBindValue(from: response, expectedRequestID: requestID)
    }

    private func send(_ request: Data, to hostname: String, port: Int) async throws -> Data {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw TransportError.connectionFailed("invalid port \(port)")
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(hostname),
            port: nwPort,
            using: .udp
        )
        let queue = DispatchQueue(label: "swiftmiko.snmpdemo.transport")
        let deadline = timeout

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            func resume(_ result: Result<Data, Error>) {
                // Every call site below (timeout, state updates, send/receive
                // completions) already runs on `queue` since the connection
                // was started with `queue`, so this check-then-set is safe
                // without an extra lock.
                guard !didResume else { return }
                didResume = true
                connection.cancel()
                continuation.resume(with: result)
            }

            queue.asyncAfter(deadline: .now() + deadline) {
                resume(.failure(TransportError.timedOut))
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { error in
                        if let error {
                            resume(.failure(TransportError.connectionFailed(error.localizedDescription)))
                            return
                        }
                        connection.receiveMessage { data, _, _, error in
                            if let error {
                                resume(.failure(TransportError.connectionFailed(error.localizedDescription)))
                            } else if let data, !data.isEmpty {
                                resume(.success(data))
                            } else {
                                resume(.failure(TransportError.emptyResponse))
                            }
                        }
                    })
                case .failed(let error):
                    resume(.failure(TransportError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    resume(.failure(TransportError.timedOut))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
