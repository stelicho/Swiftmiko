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
// Sources/Swiftmiko/Aruba/ArubaOs.swift

import Foundation

/// Aruba OS SSH driver (for Aruba OS wireless controllers — distinct
/// from the newer AOS-CX switch platform).
///
/// Maps to netmiko's ArubaOsSSH(CiscoSSHConnection).
public final class ArubaOsSSH: CiscoSSHConnection {

    /// Aruba OS requires a bare "\r" line ending, and its
    /// auto-complete-on-space behavior makes command-echo
    /// verification unreliable — both are forced here unless the
    /// caller's profile already specifies them.
    ///
    /// Maps to netmiko's __init__ override:
    ///     if kwargs.get("default_enter") is None:
    ///         kwargs["default_enter"] = "\r"
    ///     if kwargs.get("global_cmd_verify") is None:
    ///         kwargs["global_cmd_verify"] = False
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
        setGlobalCmdVerify(false)
    }

    // MARK: Session Preparation

    /// Aruba OS requires enable mode before paging can be disabled —
    /// same ordering constraint A10 has.
    ///
    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     self.enable()
    ///     self.disable_paging(command="no paging")
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()
        try await enterEnableMode(secret: profile.secret ?? "")
        try await disablePaging(command: "no paging")
    }

    // MARK: Config Mode

    /// Checks if the device is in configuration mode.
    ///
    /// Maps to netmiko's check_config_mode(check_string="(config) #").
    /// Aruba's config prompt has the shape
    /// "(<controller name>) (config) #" — same literal-space-before-#
    /// quirk seen on Silver Peak.
    override public func isInConfigMode(
        checkString: String = "(config) #",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Enter configuration mode.
    ///
    /// Maps to netmiko's config_mode(config_command="configure
    /// term"). Same auto-complete-on-space constraint as AOS-CX.
    @discardableResult
    override public func enterConfigMode(
        command: String = "configure term",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        return try await super.enterConfigMode(
            command: command,
            pattern: pattern,
            dotAll: dotAll
        )
    }
}

// MARK: - ArubaOsFileTransfer

/// Aruba OS SCP File Transfer driver.
///
/// Maps to netmiko's ArubaOsFileTransfer(BaseFileTransfer).
///
/// The defining characteristic of this class: Aruba OS has NO MD5
/// support whatsoever. Every hash-related method throws
/// notImplemented rather than attempting a checksum. Instead,
/// verifyFile() falls back to comparing raw file sizes — a much
/// weaker integrity check, but the only one this platform offers.
public final class ArubaOsFileTransfer: SCPHandler {

    /// Maps to netmiko's __init__, which defaults file_system to
    /// "/mm/mynode" and hash_supported to false.
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destinationFile: String,
        fileSystem: String = "/mm/mynode",
        direction: SCPTransferDirection = .put
    ) async throws {
        try await super.init(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destinationFile,
            fileSystem: fileSystem,
            direction: direction,
            hashSupported: false
        )
    }

    // MARK: MD5 — Unsupported

    /// Aruba OS does not support an MD5-hash operation.
    /// Maps to netmiko's compare_md5().
    override public func compareMD5() async throws -> Bool {
        throw SwiftmikoError.notImplemented(
            "Aruba OS does not support an MD5-hash operation."
        )
    }

    /// Aruba OS does not support an MD5-hash operation.
    /// Maps to netmiko's remote_md5().
    override public func remoteMD5(
        baseCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Aruba OS does not support an MD5-hash operation."
        )
    }

    // MARK: File Existence

    /// Check if the destination file already exists.
    ///
    /// Maps to netmiko's check_file_exists().
    ///
    /// For a put, runs "dir search <filename>" and looks for the
    /// exact filename as the last whitespace-separated field of any
    /// output line — Aruba's directory listing puts the filename
    /// last, unlike a typical Unix `ls -l` where it can contain
    /// embedded spaces safely because it's always the final field.
    /// For a get, falls back to checking the local filesystem
    /// directly.
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        switch direction {
        case .put:
            let command = remoteCommand.isEmpty
                ? "dir search \(destinationFileBaseName)"
                : remoteCommand
            let remoteOutput = try await connection.sendCommand(command)

            if remoteOutput.contains("Cannot get directory information") {
                return false
            }

            let matchingFilenames = remoteOutput
                .components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    let fields = line.split(separator: " ").map(String.init)
                    return fields.last
                }
            return matchingFilenames.contains(destinationFile)

        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

    // MARK: File Size

    /// Get the size of a remote file in bytes.
    ///
    /// Maps to netmiko's remote_file_size().
    ///
    /// Parses the output of "dir search <filename>", a fixed-width
    /// listing where the file size is the 5th whitespace-separated
    /// field and the filename is the last. Example line:
    ///
    ///     -rw-r--r--    1 root     root 16283 Nov  9 12:25 default.cfg
    ///
    /// Throws if the file isn't found in the listing at all, or if
    /// the size field can't be parsed as an integer — both indicate
    /// either a missing file or a command-output format Netmiko's
    /// original parsing logic didn't anticipate.
    override public func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        let targetFile: String
        if let remoteFile {
            targetFile = remoteFile
        } else {
            switch direction {
            case .put: targetFile = destinationFile
            case .get: targetFile = sourceFile
            }
        }

        let searchName = (targetFile as NSString).lastPathComponent

        let command = remoteCommand.isEmpty
            ? "dir search \(searchName)"
            : remoteCommand
        let remoteOutput = try await connection.sendCommand(command)

        if remoteOutput.contains("Cannot get directory information") {
            throw SwiftmikoError.commandFailed(
                "Unable to find file on remote system"
            )
        }

        for line in remoteOutput.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count >= 5 else { continue }
            let fileNameField = fields.last ?? ""
            if fileNameField == searchName {
                guard let size = Int(fields[4]) else {
                    throw SwiftmikoError.commandFailed(
                        "Unable to parse remote file size, wrong field " +
                        "in use or malformed command output"
                    )
                }
                return size
            }
        }

        throw SwiftmikoError.commandFailed(
            "Unable to find file on remote system"
        )
    }

    // MARK: Verification

    /// Verify the file transferred correctly, based on file size
    /// comparison only — this platform has no MD5 support.
    ///
    /// Maps to netmiko's verify_file().
    override public func verifyFile() async throws -> Bool {
        switch direction {
        case .put:
            let localSize = try FileManager.default
                .attributesOfItem(atPath: sourceFile)[.size] as? Int ?? -1
            let remoteSize = try await remoteFileSize(remoteFile: destinationFile)
            return localSize == remoteSize

        case .get:
            let remoteSize = try await remoteFileSize(remoteFile: sourceFile)
            let localSize = try FileManager.default
                .attributesOfItem(atPath: destinationFile)[.size] as? Int ?? -1
            return remoteSize == localSize
        }
    }

    // MARK: Space Available

    /// Return space available on the remote device.
    ///
    /// Maps to netmiko's remote_space_available().
    ///
    /// Parses "show storage" output — effectively Aruba's version of
    /// `df -h` — filtering for the line whose mount point is
    /// "/flash", then converts a human-readable size suffix (K, M, G,
    /// T, etc.) into a raw byte count. Sums across all matching lines
    /// since there can be more than one filesystem mounted at
    /// /flash on some controller configurations.
    override public func remoteSpaceAvailable(
        searchPattern: String = ""
    ) async throws -> Int {
        let output = try await connection.sendCommand("show storage")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let availableSizes = output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let fields = line.split(separator: " ").map(String.init)
                guard fields.last == "/flash", fields.count >= 3 else { return nil }
                return fields[fields.count - 3]
            }

        guard !availableSizes.isEmpty else {
            throw SwiftmikoError.commandFailed(
                "Could not determine remote space available."
            )
        }

        let sizeNames = ["B", "K", "M", "G", "T", "P", "E"]
        var spaceAvailable = 0.0

        for availableSize in availableSizes {
            guard let suffix = availableSize.last else {
                throw SwiftmikoError.commandFailed(
                    "Could not determine remote space available."
                )
            }
            let sizeString = String(availableSize.dropLast())

            guard let suffixIndex = sizeNames.firstIndex(of: String(suffix)) else {
                throw SwiftmikoError.commandFailed(
                    "Could not determine remote space available."
                )
            }
            guard let size = Double(sizeString) else {
                throw SwiftmikoError.commandFailed(
                    "Could not determine remote space available."
                )
            }

            spaceAvailable += size * pow(1024.0, Double(suffixIndex))
        }

        return Int(spaceAvailable)
    }

    // MARK: SCP Enable/Disable

    /// Enable SCP on the remote device.
    /// Maps to netmiko's enable_scp(cmd="service scp").
    override public func enableSCP(command: String = "service scp") async throws {
        try await super.enableSCP(command: command)
    }

    /// Disable SCP on the remote device.
    /// Maps to netmiko's disable_scp(cmd="no service scp").
    override public func disableSCP(command: String = "no service scp") async throws {
        try await super.disableSCP(command: command)
    }
}

/// Small helper for extracting a file's base name for search commands.
private extension ArubaOsFileTransfer {
    var destinationFileBaseName: String {
        (destinationFile as NSString).lastPathComponent
    }
}
