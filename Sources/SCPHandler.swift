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
//  SCPHandler.swift
//  Swiftmiko
//
//  Port of netmiko/scp_handler.py
//

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

/// A small abstraction over the SCP implementation used by Swiftmiko.
///
/// Netmiko receives an SCP client from Paramiko. Swiftmiko should not tie the
/// transfer API to one SSH package, so the eventual SwiftNIO/SSH client
/// implements this protocol and is injected into `SCPHandler`.
public protocol SCPClient: AnyObject {
    func put(sourceFile: String, destination: String) async throws
    func get(sourceFile: String, destination: String) async throws
    func close() async
}

/// A progress callback compatible with Netmiko's `progress`/`progress4`
/// callbacks. `peerName` is present for the four-argument variant.
public typealias SCPProgressCallback = (
    _ fileName: String,
    _ size: Int,
    _ sent: Int,
    _ peerName: String?
) -> Void

/// The separate SSH control connection used for an SCP transfer.
///
/// It deliberately owns only the SCP client. The interactive CLI connection
/// remains owned by `BaseConnection`.
public final class SCPConn {
    public let sshControlChannel: BaseConnection
    public let socketTimeout: TimeInterval
    public let progress: SCPProgressCallback?
    public let progress4: SCPProgressCallback?

    private var client: SCPClient?

    public init(
        sshConnection: BaseConnection,
        socketTimeout: TimeInterval = 10.0,
        progress: SCPProgressCallback? = nil,
        progress4: SCPProgressCallback? = nil,
        client: SCPClient? = nil
    ) {
        self.sshControlChannel = sshConnection
        self.socketTimeout = socketTimeout
        self.progress = progress
        self.progress4 = progress4
        self.client = client
    }

    /// Establish the SCP control channel.
    ///
    /// The client is injected because the SSH implementation is a separate
    /// Swiftmiko layer. Calling this without a client is an explicit error,
    /// rather than silently pretending a transfer succeeded.
    public func establishSCPConnection() throws {
        guard client != nil else {
            throw SwiftmikoError.connectionFailed(
                "No SCP client was supplied for the transfer"
            )
        }
    }

    /// Put a file. Kept as a compatibility alias for Netmiko's old method.
    public func scpTransferFile(
        sourceFile: String,
        destination: String
    ) async throws {
        try await putFile(sourceFile: sourceFile, destination: destination)
    }

    public func scpGetFile(
        sourceFile: String,
        destination: String
    ) async throws {
        guard let client else {
            throw SwiftmikoError.connectionFailed("SCP client is not connected")
        }
        try await client.get(sourceFile: sourceFile, destination: destination)
    }

    public func scpPutFile(
        sourceFile: String,
        destination: String
    ) async throws {
        try await putFile(sourceFile: sourceFile, destination: destination)
    }

    private func putFile(sourceFile: String, destination: String) async throws {
        guard let client else {
            throw SwiftmikoError.connectionFailed("SCP client is not connected")
        }
        try await client.put(sourceFile: sourceFile, destination: destination)
    }

    /// Close the SCP channel. Closing more than once is safe.
    public func close() async {
        await client?.close()
        client = nil
    }
}

/// Direction of an SCP transfer.
public enum SCPTransferDirection: String, Sendable {
    case put
    case get
}

/// Base class for file transfers and their remote-device bookkeeping.
///
/// This is the Swift equivalent of Netmiko's `BaseFileTransfer`.
open class SCPHandler {
    public let connection: BaseConnection
    public let sourceFile: String
    public let destinationFile: String
    public let direction: SCPTransferDirection
    public let socketTimeout: TimeInterval
    public let progress: SCPProgressCallback?
    public let progress4: SCPProgressCallback?

    public private(set) var fileSystem: String
    public private(set) var sourceMD5: String?
    public private(set) var fileSize: Int

    private let hashSupported: Bool
    private let scpClient: SCPClient?
    private var scpConnection: SCPConn?

    public init(
        connection: BaseConnection,
        sourceFile: String,
        destinationFile: String,
        fileSystem: String? = nil,
        direction: SCPTransferDirection = .put,
        socketTimeout: TimeInterval = 10.0,
        progress: SCPProgressCallback? = nil,
        progress4: SCPProgressCallback? = nil,
        hashSupported: Bool = true,
        scpClient: SCPClient? = nil
    ) async throws {
        self.connection = connection
        self.sourceFile = sourceFile
        self.destinationFile = destinationFile
        self.direction = direction
        self.socketTimeout = socketTimeout
        self.progress = progress
        self.progress4 = progress4
        self.hashSupported = hashSupported
        self.scpClient = scpClient
        self.fileSystem = ""
        self.sourceMD5 = nil
        self.fileSize = 0

        let deviceType = connection.profile.deviceType
        if let fileSystem, !fileSystem.isEmpty {
            self.fileSystem = fileSystem
        } else if deviceType.contains("cisco_ios") ||
                    deviceType.contains("cisco_xe") ||
                    deviceType.contains("cisco_xr") {
            self.fileSystem = try await connection.autodetectFileSystem()
        } else {
            throw SwiftmikoError.connectionFailed(
                "Destination filesystem must be specified for \(deviceType)"
            )
        }

        switch direction {
        case .put:
            guard FileManager.default.fileExists(atPath: sourceFile) else {
                throw SwiftmikoError.connectionFailed(
                    "Local source file does not exist: \(sourceFile)"
                )
            }
            self.fileSize = try Self.localFileSize(atPath: sourceFile)
            if hashSupported {
                self.sourceMD5 = try Self.fileMD5(
                    fileName: sourceFile,
                    addNewline: false
                )
            }

        case .get:
            self.sourceMD5 = hashSupported
                ? try await self.remoteMD5ForInitialization()
                : nil
            self.fileSize = try await self.remoteFileSize(
                remoteFile: sourceFile
            )
        }
    }

    // MARK: SCP channel

    /// Establish the second SSH/SCP connection.
    open func establishSCPConnection() async throws {
        let connection = SCPConn(
            sshConnection: connection,
            socketTimeout: socketTimeout,
            progress: progress,
            progress4: progress4,
            client: scpClient
        )
        try connection.establishSCPConnection()
        scpConnection = connection
    }

    /// Close the second SSH/SCP connection.
    open func closeSCPChannel() async {
        await scpConnection?.close()
        scpConnection = nil
    }

    // MARK: Space and existence checks

    open func remoteSpaceAvailable(
        searchPattern: String = #"(\d+) \w+ free"#
    ) async throws -> Int {
        let output = try await connection.sendCommand(
            "dir \(fileSystem)",
            stripPrompt: false,
            stripCommand: false
        )

        guard let match = firstCapture(
            pattern: searchPattern,
            in: output
        ), let value = Int(match) else {
            throw SwiftmikoError.connectionFailed(
                "Pattern \(searchPattern) was not detected in output:\n\n\(output)"
            )
        }

        if output.range(
            of: #"(?i)\d+ kbytes free"#,
            options: .regularExpression
        ) != nil {
            return value * 1_000
        }
        return value
    }

    /// Return available space on a Unix-like remote shell.
    open func remoteSpaceAvailableUnix(
        searchPattern: String = #"[#$]"#
    ) async throws -> Int {
        let output = try await connection.sendCommand(
            "/bin/df -k \(fileSystem)",
            expectString: searchPattern,
            stripPrompt: false,
            stripCommand: false
        )
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else {
            throw SwiftmikoError.connectionFailed(
                "Parsing error, unexpected output from /bin/df -k \(fileSystem):\n\(output)"
            )
        }

        let header = lines[0].split(whereSeparator: { $0 == " " || $0 == "\t" })
        let values = lines[1].split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard header.contains("Filesystem"),
              header.contains("Avail"),
              values.count > 3,
              let availableBlocks = Int(values[3]) else {
            throw SwiftmikoError.connectionFailed(
                "Parsing error, unexpected output from /bin/df -k \(fileSystem):\n\(output)"
            )
        }
        return availableBlocks * 1_024
    }

    open func localSpaceAvailable() throws -> Int {
        let attributes = try FileManager.default.attributesOfFileSystem(
            forPath: FileManager.default.currentDirectoryPath
        )
        if let free = attributes[.systemFreeSize] as? NSNumber {
            return free.intValue
        }
        throw SwiftmikoError.connectionFailed(
            "Unable to determine free space on the local filesystem"
        )
    }

    open func verifySpaceAvailable(
        searchPattern: String = #"(\d+) \w+ free"#
    ) async throws -> Bool {
        let available: Int
        switch direction {
        case .put:
            available = try await remoteSpaceAvailable(
                searchPattern: searchPattern
            )
        case .get:
            available = try localSpaceAvailable()
        }
        return available > fileSize
    }

    open func checkFileExists(remoteCommand: String = "") async throws -> Bool {
        switch direction {
        case .put:
            let command = remoteCommand.isEmpty
                ? "dir \(fileSystem)/\(destinationFile)"
                : remoteCommand
            let output = try await connection.sendCommand(
                command,
                stripPrompt: false,
                stripCommand: false
            )

            if output.contains("Error opening") ||
                output.contains("No such file or directory") ||
                output.contains("Path does not exist") {
                return false
            }

            let escapedDestination = NSRegularExpression.escapedPattern(
                for: destinationFile
            )
            let found = output.range(
                of: #"(?s)Directory of .*\#(escapedDestination)"#,
                options: .regularExpression
            ) != nil
            guard found || output.contains(destinationFile) else {
                throw SwiftmikoError.connectionFailed(
                    "Unexpected output from checkFileExists:\n\(output)"
                )
            }
            return true

        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

    open func checkFileExistsUnix(
        remoteCommand: String = "",
        searchPattern: String = #"[#$]"#
    ) async throws -> Bool {
        switch direction {
        case .put:
            let command = remoteCommand.isEmpty
                ? "/bin/ls \(fileSystem)/\(destinationFile) 2> /dev/null"
                : remoteCommand
            let output = try await connection.sendCommand(
                command,
                expectString: searchPattern,
                stripPrompt: false,
                stripCommand: false
            )
            return output.contains(destinationFile)
        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

    // MARK: File metadata

    open func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        let file = remoteFile ?? (
            direction == .put ? destinationFile : sourceFile
        )
        let command = remoteCommand.isEmpty
            ? "dir \(fileSystem)/\(file)"
            : remoteCommand
        let output = try await connection.sendCommand(
            command,
            stripPrompt: false,
            stripCommand: false
        )

        if output.contains("Error opening") ||
            output.contains("No such file or directory") {
            throw SwiftmikoError.connectionFailed(
                "Unable to find file on remote system: \(file)"
            )
        }

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let escapedName = NSRegularExpression.escapedPattern(for: fileName)
        let lines = output.components(separatedBy: .newlines)
        for line in lines where line.range(
            of: escapedName,
            options: .regularExpression
        ) != nil {
            let fields = line.split(whereSeparator: {
                $0 == " " || $0 == "\t"
            })
            // Cisco `dir` output: index, permissions, bytes, date, filename.
            if fields.count > 2, let size = Int(fields[2]) {
                return size
            }
        }

        throw SwiftmikoError.connectionFailed(
            "Unable to parse remote file size for \(file)"
        )
    }

    open func remoteFileSizeUnix(
        remoteCommand: String = "",
        remoteFile: String? = nil,
        searchPattern: String = #"[#$]"#
    ) async throws -> Int {
        let file = remoteFile ?? (
            direction == .put ? destinationFile : sourceFile
        )
        let qualifiedFile = "\(fileSystem)/\(file)"
        let command = remoteCommand.isEmpty
            ? "/bin/ls -l \(qualifiedFile)"
            : remoteCommand
        let output = try await connection.sendCommand(
            command,
            expectString: searchPattern,
            stripPrompt: false,
            stripCommand: false
        )

        if output.contains("No such file or directory") {
            throw SwiftmikoError.connectionFailed(
                "Unable to find file on remote system: \(qualifiedFile)"
            )
        }

        let escapedFile = NSRegularExpression.escapedPattern(
            for: qualifiedFile
        )
        for line in output.components(separatedBy: .newlines)
            where line.range(of: escapedFile, options: .regularExpression) != nil {
            let fields = line.split(whereSeparator: {
                $0 == " " || $0 == "\t"
            })
            // Unix `ls -l`: mode, links, owner, group, bytes, ...
            if fields.count > 4, let size = Int(fields[4]) {
                return size
            }
        }

        throw SwiftmikoError.connectionFailed(
            "Pattern not found for remote file size: \(qualifiedFile)"
        )
    }

    public static func fileMD5(
        fileName: String,
        addNewline: Bool = false
    ) throws -> String {
        var data = try Data(contentsOf: URL(fileURLWithPath: fileName))
        if addNewline {
            data.append(contentsOf: [0x0A])
        }

#if canImport(CryptoKit) || canImport(Crypto)
        return Insecure.MD5.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
#else
        throw SwiftmikoError.connectionFailed(
            "MD5 support requires CryptoKit or swift-crypto"
        )
#endif
    }

    public static func processMD5(
        _ output: String,
        pattern: String = #"=\s+(\S+)"#
    ) throws -> String {
        guard let value = firstCapture(pattern: pattern, in: output) else {
            throw SwiftmikoError.connectionFailed(
                "Invalid output from MD5 command: \(output)"
            )
        }
        return value
    }

    open func compareMD5() async throws -> Bool {
        switch direction {
        case .put:
            let remote = try await remoteMD5()
            return sourceMD5 == remote
        case .get:
            let local = try Self.fileMD5(fileName: destinationFile)
            return sourceMD5 == local
        }
    }

    open func remoteMD5(
        baseCommand: String = "verify /md5",
        remoteFile: String? = nil
    ) async throws -> String {
        let file = remoteFile ?? (
            direction == .put ? destinationFile : sourceFile
        )
        let output = try await connection.sendCommand(
            "\(baseCommand) \(fileSystem)/\(file)",
            readTimeout: 300.0,
            stripPrompt: false,
            stripCommand: false
        )
        return try Self.processMD5(output)
    }

    // MARK: Transfer operations

    open func transferFile() async throws {
        switch direction {
        case .put:
            try await putFile()
        case .get:
            try await getFile()
        }
    }

    open func getFile() async throws {
        guard let scpConnection else {
            throw SwiftmikoError.connectionFailed(
                "SCP connection has not been established"
            )
        }
        try await scpConnection.scpGetFile(
            sourceFile: "\(fileSystem)/\(sourceFile)",
            destination: destinationFile
        )
        await closeSCPChannel()
    }

    open func putFile() async throws {
        guard let scpConnection else {
            throw SwiftmikoError.connectionFailed(
                "SCP connection has not been established"
            )
        }
        try await scpConnection.scpTransferFile(
            sourceFile: sourceFile,
            destination: "\(fileSystem)/\(destinationFile)"
        )
        // Closing flushes the remote file on Cisco devices.
        await closeSCPChannel()
    }

    open func verifyFile() async throws -> Bool {
        try await compareMD5()
    }

    open func enableSCP(command: String = "ip scp server enable") async throws {
        _ = try await connection.sendConfigSet([command])
    }

    open func disableSCP(
        command: String = "no ip scp server enable"
    ) async throws {
        _ = try await connection.sendConfigSet([command])
    }

    // MARK: Helpers

    private func remoteMD5ForInitialization() async throws -> String {
        try await remoteMD5(remoteFile: sourceFile)
    }

    private static func localFileSize(atPath path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let size = attributes[.size] as? NSNumber else {
            throw SwiftmikoError.connectionFailed(
                "Unable to determine local file size: \(path)"
            )
        }
        return size.intValue
    }

    private func firstCapture(
        pattern: String,
        in value: String
    ) -> String? {
        Self.firstCapture(pattern: pattern, in: value)
    }

    private static func firstCapture(
        pattern: String,
        in value: String
    ) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[capture])
    }
}

/// Netmiko's dispatcher exposes a `FileTransfer` class. This type identity
/// keeps that public concept available while using Swiftmiko's common handler.
open class FileTransfer: SCPHandler {}

/// Compatibility name used by the Cisco connection layer.
public typealias BaseFileTransfer = SCPHandler
