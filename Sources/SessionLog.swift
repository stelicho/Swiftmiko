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
//
//  SessionLog.swift
//  Swiftmiko
//
//  Port of netmiko/session_log.py
//

import Foundation

public enum SessionLogMode: String, Sendable {
    case write
    case append
}

/// Destination used by `SessionLog`.
public protocol SessionLogSink: AnyObject {
    func write(_ data: Data) throws
    func flush() throws
    func close() throws
}

/// An in-memory sink useful for tests and callers that want a transcript
/// without creating a file.
public final class MemorySessionLogSink: SessionLogSink {
    public private(set) var data = Data()

    public init() {}

    public func write(_ data: Data) throws {
        self.data.append(data)
    }

    public func flush() throws {}
    public func close() throws {}

    public var string: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

private final class FileSessionLogSink: SessionLogSink {
    private var handle: FileHandle

    init(path: String, mode: SessionLogMode) throws {
        if mode == .write {
            FileManager.default.createFile(
                atPath: path,
                contents: Data()
            )
        } else if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(
                atPath: path,
                contents: Data()
            )
        }

        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        if mode == .append {
            try handle.seekToEnd()
        }
    }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    func flush() throws {
        try handle.synchronize()
    }

    func close() throws {
        try handle.close()
    }
}

/// Secret-filtering session transcript.
///
/// Like Netmiko's implementation, data is held briefly in memory so a secret
/// split across two channel reads is still filtered before it reaches the
/// underlying file or buffer.
public final class SessionLog {
    public let fileName: String?
    public let fileMode: SessionLogMode
    public let fileEncoding: String.Encoding
    public let recordWrites: Bool
    public let noLog: [String: String]

    /// Set by the connection before its final write. Exposed for parity with
    /// Netmiko; the filtering behavior is always applied regardless.
    public var fin = false

    private var sink: SessionLogSink?
    private var ownsSink = false
    private var sessionBuffer: String

    public init(
        fileName: String? = nil,
        bufferedIO: SessionLogSink? = nil,
        fileMode: SessionLogMode = .write,
        fileEncoding: String.Encoding = .utf8,
        noLog: [String: String] = [:],
        recordWrites: Bool = false,
        sessionBuffer: String = ""
    ) {
        self.fileName = fileName
        self.fileMode = fileMode
        self.fileEncoding = fileEncoding
        self.noLog = noLog
        self.recordWrites = recordWrites
        self.sessionBuffer = sessionBuffer

        if fileName == nil {
            self.sink = bufferedIO
            self.ownsSink = false
        } else {
            self.sink = nil
            self.ownsSink = true
        }
    }

    /// Compatibility initializer accepting Netmiko's string mode.
    public convenience init(
        fileName: String? = nil,
        bufferedIO: SessionLogSink? = nil,
        fileMode: String = "write",
        fileEncoding: String.Encoding = .utf8,
        noLog: [String: String] = [:],
        recordWrites: Bool = false,
        sessionBuffer: String = ""
    ) {
        self.init(
            fileName: fileName,
            bufferedIO: bufferedIO,
            fileMode: SessionLogMode(rawValue: fileMode) ?? .write,
            fileEncoding: fileEncoding,
            noLog: noLog,
            recordWrites: recordWrites,
            sessionBuffer: sessionBuffer
        )
    }

    public func open() throws {
        guard let fileName else { return }
        sink = try FileSessionLogSink(path: fileName, mode: fileMode)
        ownsSink = true
    }

    public func close() throws {
        flush(final: true)
        if ownsSink {
            try sink?.close()
            sink = nil
        }
    }

    /// Replace every configured secret with a fixed mask.
    public func noLogFilter(_ data: String) -> String {
        noLog.values.reduce(data) { result, hidden in
            result.replacingOccurrences(of: hidden, with: "********")
        }
    }

    private func longestPartialMatch(_ data: String) -> Int {
        var holdBack = 0
        for hidden in noLog.values where hidden.count > 1 {
            let maximum = min(hidden.count - 1, data.count)
            guard maximum > 0 else { continue }
            for length in 1...maximum {
                if data.hasSuffix(String(hidden.prefix(length))) {
                    holdBack = max(holdBack, length)
                }
            }
        }
        return holdBack
    }

    private func readBuffer() -> String {
        let data = sessionBuffer
        sessionBuffer = ""
        return data
    }

    private func writeToSink(_ data: String) {
        guard !data.isEmpty, let sink else { return }
        guard let encoded = data.data(using: fileEncoding) else { return }
        try? sink.write(encoded)
        try? sink.flush()
    }

    private func flush(final: Bool = false) {
        guard sink != nil else { return }
        var data = readBuffer()

        if !noLog.isEmpty && !data.isEmpty {
            let holdBack = longestPartialMatch(data)
            if holdBack > 0 {
                if final {
                    data = String(data.dropLast(holdBack)) + "********"
                } else {
                    sessionBuffer = String(data.suffix(holdBack))
                    data = String(data.dropLast(holdBack))
                }
            }
            data = noLogFilter(data)
        }

        writeToSink(data)
    }

    public func flush() {
        flush(final: false)
    }

    public func write(_ data: String) {
        guard !data.isEmpty else { return }
        sessionBuffer += data
        flush()
    }
}
