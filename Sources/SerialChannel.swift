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
public final class SerialChannel: Swiftmiko.Channel, @unchecked Sendable {
    private let portPath: String
    private let settings: SerialSettings
    private var fd: Int32 = -1

    private let lock = NSLock()
    private var inputBuffer = Data()

    public private(set) var isOpen = false

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

        fd = rawFD
        isOpen = true
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
        let data = lock.withLock {
            let d = inputBuffer; inputBuffer = Data(); return d
        }
        if data.isEmpty { return "" }
        return String(bytes: data, encoding: .utf8)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? ""
    }

    public func close() async {
        isOpen = false
#if canImport(Darwin)
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
#endif
    }

    // MARK: Private

    private func writeRaw(_ bytes: [UInt8]) throws {
#if canImport(Darwin)
        let data = Data(bytes)
        var total = 0
        while total < data.count {
            let n = data.withUnsafeBytes { ptr -> Int in
                Darwin.write(fd, ptr.baseAddress!.advanced(by: total), ptr.count - total)
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
        while isOpen && fd >= 0 {
            let n = Darwin.read(fd, &buf, buf.count)
            if n > 0 {
                lock.withLock { inputBuffer.append(contentsOf: buf.prefix(n)) }
            } else if n == 0 {
                break  // EOF / device removed
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
