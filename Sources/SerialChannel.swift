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
//  SerialChannel.swift
//  Swiftmiko
//
//  Channel implementation for direct serial console connections,
//  backed by POSIX termios and a background reader thread.
//
//  Set ConnectionProfile.host to the serial device path, e.g.
//  "/dev/cu.usbserial-12345" on macOS. Authentication is handled
//  by the CLI session (serialLogin/telnetLogin), not at transport level.
//

import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Serial settings

/// Configuration for a serial port connection.
///
/// Mirrors the `serial_settings` dict accepted by Python Netmiko's
/// `cisco_ios_serial` and similar device types.
public struct SerialSettings: Sendable, Equatable {
    /// Port speed in bits per second (e.g. 9600, 115200). Defaults to 9600.
    public var baudRate: Int
    /// Data bits per character: 5–8. Defaults to 8.
    public var dataBits: Int
    /// Stop bits: 1 or 2. Defaults to 1.
    public var stopBits: Int
    /// Parity. Defaults to `.none`.
    public var parity: Parity

    public enum Parity: Sendable, Equatable {
        case none, even, odd
    }

    public init(
        baudRate: Int = 9600,
        dataBits: Int = 8,
        stopBits: Int = 1,
        parity: Parity = .none
    ) {
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.stopBits = stopBits
        self.parity = parity
    }

    public static let `default` = SerialSettings()
}

// MARK: - SerialChannel

/// Direct serial console transport conforming to the Swiftmiko Channel
/// protocol.
///
/// The `host` field in `ConnectionProfile` must be the device path, e.g.
/// `"/dev/cu.usbserial-12345"`. The optional `serialSettings` field
/// controls baud rate and framing; the defaults (9600 8N1) match Netmiko.
///
/// A background thread reads continuously from the port and fills an
/// internal buffer. `readAvailable()` drains that buffer without blocking,
/// matching the non-blocking contract shared by NIOSSHChannel and
/// NIOTelnetChannel.
///
/// `fd` and `isOpen` are read from both the calling thread (open/close/
/// write) and the background read-loop thread, so both are guarded by
/// `lock` alongside `inputBuffer` — a bare unsynchronized `Int32`/`Bool`
/// here would let `close()` race the read loop's `Darwin.read(fd, ...)`
/// call, risking a read against an already-closed (and potentially
/// reused) file descriptor.
public final class SerialChannel: Swiftmiko.Channel, @unchecked Sendable {
    private let portPath: String
    private let settings: SerialSettings

    private let lock = NSLock()
    private var _fd: Int32 = -1
    private var _isOpen = false
    private var inputBuffer = Data()

    public var isOpen: Bool {
        lock.withLock { _isOpen }
    }

    public init(profile: ConnectionProfile) {
        self.portPath = profile.host
        self.settings = profile.serialSettings ?? .default
    }

    // MARK: Channel

    public func open() async throws {
#if canImport(Darwin)
        let rawFD = Darwin.open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard rawFD >= 0 else {
            throw SwiftmikoError.connectionFailed(
                "Cannot open serial port \(portPath): \(String(cString: strerror(errno)))"
            )
        }

        // Switch to blocking mode; VTIME provides the read timeout.
        var flags = fcntl(rawFD, F_GETFL)
        flags &= ~O_NONBLOCK
        _ = fcntl(rawFD, F_SETFL, flags)

        var tty = termios()
        cfmakeraw(&tty)
        cfsetspeed(&tty, speed_t(settings.baudRate))

        // Data bits (cfmakeraw already sets CS8; override if requested)
        if settings.dataBits != 8 {
            let csize: tcflag_t
            switch settings.dataBits {
            case 5: csize = tcflag_t(CS5)
            case 6: csize = tcflag_t(CS6)
            case 7: csize = tcflag_t(CS7)
            default: csize = tcflag_t(CS8)
            }
            tty.c_cflag &= ~tcflag_t(CSIZE)
            tty.c_cflag |= csize
        }

        // Stop bits
        if settings.stopBits == 2 {
            tty.c_cflag |= tcflag_t(CSTOPB)
        } else {
            tty.c_cflag &= ~tcflag_t(CSTOPB)
        }

        // Parity
        switch settings.parity {
        case .none:
            tty.c_cflag &= ~tcflag_t(PARENB)
        case .even:
            tty.c_cflag |= tcflag_t(PARENB)
            tty.c_cflag &= ~tcflag_t(PARODD)
        case .odd:
            tty.c_cflag |= tcflag_t(PARENB)
            tty.c_cflag |= tcflag_t(PARODD)
        }

        // VMIN=0, VTIME=1 → non-blocking read with 100 ms timeout.
        // c_cc is a fixed-size C array imported as a homogeneous tuple;
        // pointer arithmetic into the first element is the safe way to
        // access arbitrary indices.
        withUnsafeMutablePointer(to: &tty.c_cc.0) { base in
            base.advanced(by: Int(VMIN)).pointee  = 0
            base.advanced(by: Int(VTIME)).pointee = 1
        }

        guard tcsetattr(rawFD, TCSANOW, &tty) == 0 else {
            Darwin.close(rawFD)
            throw SwiftmikoError.connectionFailed(
                "tcsetattr failed for \(portPath): \(String(cString: strerror(errno)))"
            )
        }

        lock.withLock {
            _fd = rawFD
            _isOpen = true
        }
        startReadLoop()
#else
        throw SwiftmikoError.notImplemented(
            "Serial ports are only supported on Darwin/macOS"
        )
#endif
    }

    /// No-op: serial credentials are exchanged via the CLI session
    /// using serialLogin() / telnetLogin().
    public func authenticate(username: String, using method: AuthMethod) async throws {}

    public func write(_ data: String) async throws {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        try writeRaw(Array(data.utf8))
    }

    /// Returns all buffered data (non-blocking). Returns "" if the buffer
    /// is empty; the caller's readUntilPattern() loop handles retries.
    public func readAvailable() async throws -> String {
        guard isOpen else { throw SwiftmikoError.channelClosed }
        return lock.withLock {
            let (text, remaining) = Self.decodeAvailableText(from: inputBuffer)
            inputBuffer = remaining
            return text
        }
    }

    /// Decode the longest prefix of `buffer` that is valid, complete
    /// UTF-8, returning the decoded text plus whatever undecoded tail
    /// should stay buffered for a future call to complete.
    ///
    /// A multi-byte UTF-8 character can be split across two separate
    /// read() calls. Trimming up to 3 trailing bytes (the longest a
    /// dangling partial sequence can be) off the end before decoding
    /// lets the complete prefix decode correctly, leaving the partial
    /// tail for next time — rather than falling back to Latin-1 and
    /// misreading a split multi-byte character as separate single-byte
    /// ones. Only falls back to Latin-1 (for the WHOLE buffer) when
    /// trimming still doesn't produce valid UTF-8 — i.e. the data
    /// genuinely isn't UTF-8, not just split mid-character.
    ///
    /// Pulled out as a pure, static function (no channel/threading
    /// involved) specifically so this decoding edge case is testable
    /// without a real serial port.
    static func decodeAvailableText(from buffer: Data) -> (text: String, remaining: Data) {
        guard !buffer.isEmpty else { return ("", buffer) }

        let maxTrim = min(3, buffer.count - 1)
        var trim = 0
        while trim <= maxTrim {
            let decodableLength = buffer.count - trim
            if let string = String(bytes: buffer.prefix(decodableLength), encoding: .utf8) {
                return (string, buffer.dropFirst(decodableLength))
            }
            trim += 1
        }

        let fallback = String(bytes: buffer, encoding: .isoLatin1) ?? ""
        return (fallback, Data())
    }

    public func close() async {
#if canImport(Darwin)
        let fdToClose: Int32? = lock.withLock {
            guard _isOpen else { return nil }
            _isOpen = false
            let f = _fd
            _fd = -1
            return f
        }
        if let fdToClose, fdToClose >= 0 {
            Darwin.close(fdToClose)
        }
#else
        lock.withLock { _isOpen = false }
#endif
    }

    // MARK: Private

    private func writeRaw(_ bytes: [UInt8]) throws {
#if canImport(Darwin)
        let targetFD = lock.withLock { _fd }
        guard targetFD >= 0 else { throw SwiftmikoError.channelClosed }

        let data = Data(bytes)
        var total = 0
        while total < data.count {
            let n = data.withUnsafeBytes { ptr -> Int in
                Darwin.write(targetFD, ptr.baseAddress!.advanced(by: total), ptr.count - total)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw SwiftmikoError.connectionFailed(
                    "Serial write error: \(String(cString: strerror(errno)))"
                )
            }
            total += n
        }
#endif
    }

    private func startReadLoop() {
        let t = Thread { [weak self] in self?.readLoop() }
        t.qualityOfService = .utility
        t.name = "swiftmiko.serial.reader"
        t.start()
    }

    private func readLoop() {
#if canImport(Darwin)
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let (open, currentFD): (Bool, Int32) = lock.withLock { (_isOpen, _fd) }
            guard open, currentFD >= 0 else { break }

            let n = Darwin.read(currentFD, &buf, buf.count)
            if n > 0 {
                lock.withLock { inputBuffer.append(contentsOf: buf.prefix(n)) }
            } else if n == 0 {
                // VMIN=0, VTIME=1 means this read was opened in POSIX
                // termios "Case C" (MIN==0, TIME>0): per the termios(4)
                // spec, a 0-byte return here means the 100ms read timer
                // expired with no data available — NOT end-of-file.
                // Treating it as a disconnect would kill this loop after
                // the device's very first idle moment, which is
                // virtually guaranteed in any real interactive session.
                continue
            } else {
                if errno == EAGAIN || errno == EINTR {
                    Thread.sleep(forTimeInterval: 0.01)
                } else {
                    break
                }
            }
        }
#endif
    }
}

// MARK: - Provider

public let serialChannelProvider: ChannelProvider = { profile in
    SerialChannel(profile: profile)
}
