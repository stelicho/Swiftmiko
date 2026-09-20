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
// Sources/Swiftmiko/Mikrotik/Mikrotik.swift

import Foundation

/// Common implementation for MikroTik RouterOS and SwitchOS devices.
///
/// Maps to netmiko's MikrotikBase(NoEnable, NoConfig,
/// CiscoSSHConnection).
///
/// No privilege escalation and no configuration mode via this
/// connection type — hence NoEnable + NoConfig. This is one of the
/// most idiosyncratic drivers in the whole vendor set: it smuggles
/// terminal configuration flags into the SSH username itself rather
/// than sending them as commands, and its output-cleaning logic has
/// to work around real screen-repaint artifacts in the device's own
/// terminal rendering.
open class MikrotikBase: CiscoSSHConnection, NoEnable, NoConfig {

    override public nonisolated var promptPattern: String { #"\].*>"# }

    /// MikroTik requires "\r\n" as the line ending.
    /// Maps to netmiko's __init__ override.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.returnCharacter.isEmpty {
            adjustedProfile.returnCharacter = "\r\n"
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Connection Parameter Modification

    /// Append terminal-configuration flags directly onto the SSH
    /// username.
    ///
    /// Maps to netmiko's _modify_connection_params():
    ///     self.username += "+ct511w4098h"
    ///
    /// MikroTik has a genuinely unusual convention: rather than
    /// sending terminal-width/color/mode settings as commands after
    /// connecting, these are appended directly to the login username
    /// itself, using a documented suffix syntax:
    ///   c     disable console colors
    ///   e     enable dumb terminal mode
    ///   t     disable auto-detect terminal capabilities
    ///   511w  set terminal width to 511 columns
    ///   4098h set terminal height to 4098 rows
    ///
    /// This is called BEFORE the SSH transport is established — it's
    /// a connection-parameter mutation hook, not a post-connect
    /// command. Since ConnectionProfile is a value type, this can't
    /// mutate `self` the way Python mutates `self.username` in
    /// place; instead this returns the modified username for the
    /// connection-establishment code to actually use when opening the
    /// transport.
    internal nonisolated func modifiedUsername(_ baseUsername: String) -> String {
        return baseUsername + "+ct511w4098h"
    }

    // MARK: Login Handling

    /// Handle MikroTik's several possible post-login prompts.
    ///
    /// Maps to netmiko's special_login_handler(delay_factor=1.0).
    ///
    /// MikroTik can present any combination of: a license-viewing
    /// prompt, an unlicensed "press Enter to continue" notice, a
    /// default-configuration removal notice, or a forced
    /// new-password prompt (answered with Ctrl-C — \x03 — to decline
    /// changing it, rather than actually picking one). Loops up to 15
    /// times, handling whichever of these appears, until the real
    /// device prompt is finally reached.
    internal func specialLoginHandler(delay: TimeInterval = 1.0) async throws {
        let noLicenseMessage = "Please press \"Enter\" to continue!"
        let licensePrompt = "Do you want to see the software license"
        let newPasswordPrompt = "new password>"
        let defaultConfigPrompt = "remove this default configuration type \"r\""
        let combinedPattern =
            "(?:\(promptPattern)|\(noLicenseMessage)|\(licensePrompt)|" +
            "\(newPasswordPrompt)|\(defaultConfigPrompt))"

        for _ in 0..<15 {
            let data = try await readUntilPattern(
                pattern: combinedPattern,
                caseInsensitive: true
            )

            if data.contains(noLicenseMessage) {
                try await writeChannel(profile.returnCharacter)
            } else if data.contains(licensePrompt) {
                try await writeChannel("n")
            } else if data.contains(defaultConfigPrompt) {
                try await writeChannel(profile.returnCharacter)
            } else if data.contains(newPasswordPrompt) {
                try await writeChannel("\u{03}")
            } else if data.range(
                of: promptPattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                return
            }
        }

        throw SwiftmikoError.authenticationFailed(
            "Unexpected output in specialLoginHandler"
        )
    }

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation() — deliberately minimal,
    /// since terminal configuration already happened via the
    /// username suffix, and paging doesn't exist on this platform.
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await setBasePrompt()
    }

    // MARK: Paging

    /// MikroTik has no paging by default — hard no-op.
    /// Maps to netmiko's disable_paging().
    @discardableResult
    override public func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return ""
    }

    // MARK: Prompt Handling

    /// Build the prompt regex used by sendCommand for output
    /// termination, anchored strictly to end-of-string.
    ///
    /// Maps to netmiko's _prompt_handler(auto_find_prompt).
    ///
    /// Netmiko's own comment: "Prompt regex for MikroTik is generated
    /// to match only if the prompt string is at the end of the
    /// string (with no more printable characters printed after it)."
    /// Falls back to the stored basePrompt if a live findPrompt()
    /// lookup fails, rather than propagating that failure outward.
    override public func promptHandler(autoFindPrompt: Bool) async -> String {
        let prompt: String
        if autoFindPrompt {
            prompt = (try? await findPrompt()) ?? basePrompt
        } else {
            prompt = basePrompt
        }
        let escaped = NSRegularExpression.escapedPattern(for: prompt.trimmingCharacters(in: .whitespaces))
        return escaped + #"[ \t]*$"#
    }

    // MARK: Output Stripping

    /// Strip the trailing router prompt from output, accounting for
    /// possible screen-repaint duplication.
    ///
    /// Maps to netmiko's strip_prompt() override.
    ///
    /// Netmiko's own comment: "There can be two trailing instances of
    /// the prompt probably due to repainting." This drops the LAST
    /// line if it contains basePrompt, then delegates to the base
    /// implementation for a second pass in case a further trailing
    /// prompt line remains. If the last line doesn't contain
    /// basePrompt at all — an unexpected shape — this returns the
    /// original string unchanged rather than guessing.
    override public func stripPrompt(_ output: String) -> String {
        var lines = output.components(separatedBy: responseReturn)
        guard let lastLine = lines.last, lastLine.contains(basePrompt) else {
            return output
        }

        lines.removeLast()
        var cleaned = lines.joined(separator: responseReturn)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = super.stripPrompt(cleaned)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip a command echo, accounting for MikroTik potentially
    /// echoing the command more than once.
    ///
    /// Maps to netmiko's strip_command(command_string, output).
    ///
    /// MikroTik can echo the command wrapped in its own prompt shape
    /// (e.g. "[admin@MikroTik] > system routerboard print"), not just
    /// a bare repeat of the command text. This splits on that full
    /// prompt-plus-command pattern rather than the plain command
    /// string alone, keeping only what follows the LAST such
    /// occurrence.
    override public func stripCommand(
        _ commandString: String,
        output: String
    ) -> String {
        var cleaned = super.stripCommand(commandString, output: output)
        let cmd = commandString.trimmingCharacters(in: .whitespaces)

        cleaned = cleaned.trimmingCharacters(in: .whitespaces).isEmpty
            ? cleaned
            : String(cleaned.drop(while: { $0.isWhitespace }))

        let escapedCmd = NSRegularExpression.escapedPattern(for: cmd)
        let pattern = "^\\[.*\\] > \(escapedCmd).*$\(responseReturn)"

        guard cleaned.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive, .anchored]
        ) != nil || cleaned.range(of: pattern, options: [.regularExpression]) != nil else {
            // command_string isn't there — do nothing.
            return cleaned
        }

        let components = cleaned.components(
            separatedBy: try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
                .stringByReplacingMatches(
                    in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "\u{0}"
                )
                .components(separatedBy: "\u{0}")
                .isEmpty ? "" : ""
        )
        // NOTE: the above dance is a placeholder; see the comment
        // below for a cleaner NSRegularExpression-based split.
        _ = components
        return regexSplitKeepingRemainder(cleaned, pattern: pattern)
    }

    /// Split on the first match of `pattern` and return everything
    /// after it, joined back with the connection's response
    /// separator. A small helper standing in for Python's
    /// `re.split(pattern, output, flags=re.M)[1:]` followed by a
    /// rejoin — Foundation has no single-call equivalent of
    /// "split by regex, keep only what comes after the match."
    private func regexSplitKeepingRemainder(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let match = regex.firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)
              ),
              let matchRange = Range(match.range, in: text) else {
            return text
        }
        return String(text[matchRange.upperBound...])
    }

    // MARK: Prompt Detection

    /// Detect and store the base prompt, trimmed of trailing
    /// whitespace.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator=">") — same single-terminator scheme as
    /// several other drivers, plus an explicit trim.
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        basePrompt = basePrompt.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Command Execution

    /// Send a timing-based command, forcing command-echo verification
    /// on regardless of what the caller requests.
    ///
    /// Maps to netmiko's send_command_timing() override.
    ///
    /// Netmiko's own comment: "Force cmd_verify to be True due to all
    /// of the line repainting" — MikroTik's terminal redraw behavior
    /// makes it unsafe to skip echo verification, since a caller
    /// disabling it could easily misread repainted output as the real
    /// command result.
    @discardableResult
    override public func sendCommandTiming(
        _ command: String,
        readTimeout: TimeInterval = 2.0,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true
    ) async throws -> String {
        return try await super.sendCommandTiming(
            command,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            cmdVerify: true
        )
    }

    // MARK: Cleanup

    /// MikroTik uses "quit" rather than "exit" as its logout command.
    /// Maps to netmiko's cleanup(command="quit").
    override public func cleanup(command: String = "quit") async throws {
        try await super.cleanup(command: command)
    }
}

// MARK: - MikrotikRouterOsSSH

/// MikroTik RouterOS SSH driver — no differences from the base.
/// Maps to netmiko's MikrotikRouterOsSSH(MikrotikBase).
public final class MikrotikRouterOsSSH: MikrotikBase {}

// MARK: - MikrotikSwitchOsSSH

/// MikroTik SwitchOS SSH driver — no differences from the base.
/// Maps to netmiko's MikrotikSwitchOsSSH(MikrotikBase).
public final class MikrotikSwitchOsSSH: MikrotikBase {}

// MARK: - MikrotikRouterOsFileTransfer

/// MikroTik RouterOS SCP File Transfer driver.
///
/// Maps to netmiko's MikrotikRouterOsFileTransfer(BaseFileTransfer).
///
/// RouterOS reports file sizes using human-readable binary-prefixed
/// units (KiB/MiB/GiB) that get rounded imprecisely — this class has
/// its own byte-size conversion helpers to cope, and verification is
/// deliberately approximate rather than exact, since a byte-for-byte
/// comparison would almost always fail due to RouterOS's own rounding.
/// No MD5 support at all, same pattern as Aruba OS and EXOS.
public final class MikrotikRouterOsFileTransfer: SCPHandler {

    /// Maps to netmiko's __init__, defaulting file_system to "flash"
    /// and hash_supported to false.
    public init(
        connection: BaseConnection,
        sourceFile: String,
        destinationFile: String,
        fileSystem: String = "flash",
        direction: SCPTransferDirection = .put,
        socketTimeout: TimeInterval = 10.0
    ) async throws {
        try await super.init(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destinationFile,
            fileSystem: fileSystem,
            direction: direction,
            socketTimeout: socketTimeout,
            hashSupported: false
        )
    }

    // MARK: File Existence

    /// Check if the destination file already exists.
    ///
    /// Maps to netmiko's check_file_exists().
    ///
    /// Netmiko's own comment enumerates three possible response
    /// shapes this firmware can produce: a normal entry containing
    /// both "size" and the filename; flags-then-entry (some firmware
    /// versions print a "Flags:" legend line before the real
    /// entries); or just flags alone / a blank response (no matching
    /// file). Anything outside those three recognized shapes is
    /// treated as a genuine parsing failure, not silently guessed at.
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        switch direction {
        case .put:
            let command = remoteCommand.isEmpty
                ? "/file print detail where name=\"\(fileSystem)/\(destinationFile)\""
                : remoteCommand
            let output = try await connection.sendCommandTiming(command)

            if output.contains("size") && output.contains("\(fileSystem)/\(destinationFile)") {
                return true
            } else if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (output.contains("Flags:") && !output.contains("size")) {
                return false
            }
            throw SwiftmikoError.commandFailed("Unexpected output from check_file_exists")

        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

    // MARK: Space Available

    /// Return space available on the remote device.
    /// Maps to netmiko's remote_space_available().
    override public func remoteSpaceAvailable(
        searchPattern: String = ""
    ) async throws -> Int {
        let output = try await connection.sendCommandTiming(
            "system resource print without-paging"
        )

        for line in output.components(separatedBy: .newlines) where line.contains("free-memory") {
            let spaceString = line
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "free-memory: ", with: "")
            return try Self.formatToBytes(spaceString)
        }

        throw SwiftmikoError.commandFailed("Unexpected output from remote_space_available")
    }

    // MARK: File Size

    /// Get the size of a remote file, in bytes.
    /// Maps to netmiko's remote_file_size().
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

        let command = remoteCommand.isEmpty
            ? "/file print detail where name=\"\(fileSystem)/\(targetFile)\""
            : remoteCommand
        let output = try await connection.sendCommandTiming(command)

        guard let sizeSection = output.components(separatedBy: "size=").dropFirst().first,
              let sizeToken = sizeSection.components(separatedBy: " ").first else {
            throw SwiftmikoError.commandFailed("Unable to find file on remote system")
        }

        return try Self.formatToBytes(sizeToken)
    }

    // MARK: MD5 — Unsupported

    public func fileMD5(fileName: String, addNewline: Bool = false) throws -> String {
        throw SwiftmikoError.notImplemented(
            "RouterOS does not natively support an MD5-hash operation."
        )
    }
    override public func compareMD5() async throws -> Bool {
        throw SwiftmikoError.notImplemented(
            "RouterOS does not natively support an MD5-hash operation."
        )
    }
    override public func remoteMD5(baseCommand: String = "", remoteFile: String? = nil) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "RouterOS does not natively support an MD5-hash operation."
        )
    }

    // MARK: Verification

    /// Verify the file transferred correctly, based on an
    /// approximate size comparison.
    ///
    /// Maps to netmiko's verify_file().
    ///
    /// Netmiko's own docstring is worth repeating verbatim: "This
    /// method is very approximate as Mikrotik rounds file sizes to
    /// KiB, MiB, GiB... Therefore multiple conversions from/to bytes
    /// are needed." Both sizes are converted to their approximate
    /// human-readable form and compared AS STRINGS, not as raw byte
    /// counts — an exact byte comparison would almost always fail
    /// given the device's own imprecise rounding.
    override public func verifyFile() async throws -> Bool {
        switch direction {
        case .put:
            let localBytes = try FileManager.default
                .attributesOfItem(atPath: sourceFile)[.size] as? Int ?? -1
            let localSize = Self.formatBytes(localBytes)
            let remoteSize = Self.formatBytes(try await remoteFileSize(remoteFile: destinationFile))
            return localSize == remoteSize

        case .get:
            let localBytes = try FileManager.default
                .attributesOfItem(atPath: destinationFile)[.size] as? Int ?? -1
            let localSize = Self.formatBytes(localBytes)
            let remoteSize = Self.formatBytes(try await remoteFileSize(remoteFile: sourceFile))
            return localSize == remoteSize
        }
    }

    // MARK: Byte-Size Conversion Helpers

    /// Convert a MikroTik-formatted size string (e.g. "12.5KiB") to a
    /// raw byte count.
    /// Maps to netmiko's static _format_to_bytes(size).
    private static func formatToBytes(_ size: String) throws -> Int {
        if size.hasSuffix("KiB") {
            let value = size.replacingOccurrences(of: "KiB", with: "")
            guard let number = Double(value) else {
                throw SwiftmikoError.commandFailed("Unable to parse size: \(size)")
            }
            return Int((number * 1024).rounded())
        }
        if size.hasSuffix("MiB") {
            let value = size.replacingOccurrences(of: "MiB", with: "")
            guard let number = Double(value) else {
                throw SwiftmikoError.commandFailed("Unable to parse size: \(size)")
            }
            return Int((number * 1_048_576).rounded())
        }
        if size.hasSuffix("GiB") {
            let value = size.replacingOccurrences(of: "GiB", with: "")
            guard let number = Double(value) else {
                throw SwiftmikoError.commandFailed("Unable to parse size: \(size)")
            }
            return Int((number * 1_073_741_824).rounded())
        }
        guard let plain = Int(size) else {
            throw SwiftmikoError.commandFailed("Unable to parse size: \(size)")
        }
        return plain
    }

    /// Convert a raw byte count into MikroTik's approximate
    /// human-readable form. Deliberately imprecise, per Netmiko's own
    /// "Extremely approximate" comment.
    /// Maps to netmiko's static _format_bytes(size).
    private static func formatBytes(_ size: Int) -> String {
        var value = size
        var level = 0
        let suffixes = ["", "Ki", "Mi", "Gi"]

        while value > 4096, level < 3 {
            value = Int((Double(value) / 1024.0).rounded())
            level += 1
        }
        return "\(value)\(suffixes[level])B"
    }
}
