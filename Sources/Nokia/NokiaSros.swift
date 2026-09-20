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
// Sources/Swiftmiko/Nokia/NokiaSros.swift

import Foundation

/// Nokia SR OS SSH/Telnet driver.
///
/// Maps to netmiko's NokiaSros(BaseConnection).
///
/// The single most branching-heavy driver in this vendor set: SR OS
/// runs one of two fundamentally different CLI dialects, and nearly
/// every method here checks at runtime which one is active by
/// looking for an "@" character in basePrompt.
///
///   Classical CLI    No real config-mode concept, no terminal-width
///                     command, command-echo verification must be
///                     disabled since auto-complete-on-space can't be
///                     turned off. Enable step uses "enable-admin".
///
///   Model-driven CLI Genuine exclusive-edit config mode with
///                     candidate/commit/discard semantics, terminal
///                     width IS configurable, auto-complete-on-space
///                     CAN be disabled. Enable step uses plain
///                     "enable". Prompt always contains "@".
///
/// Per Netmiko's own docstring, exit_enable_mode() is explicitly
/// disabled — SR OS has no notion of exiting administrative mode
/// once entered.
open class NokiaSros: BaseConnection {

    // MARK: Session Preparation

    /// Maps to netmiko's session_preparation().
    ///
    /// Detects which CLI dialect is active immediately after prompt
    /// detection, then branches its ENTIRE remaining setup sequence
    /// based on that.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()

        if basePrompt.contains("@") {
            // Model-driven CLI.
            _ = try await disableCompleteOnSpace()
            try await setTerminalWidth(
                command: "environment console width 512",
                pattern: "environment"
            )
            try await disablePaging(command: "environment more false")
            try await disablePaging(command: "//environment no more")
        } else {
            // Classical CLI has no method to set terminal width, nor
            // to disable command-complete-on-space; consequently
            // command-echo verification must be disabled instead,
            // but only if the caller hasn't already set it explicitly.
            if globalCmdVerify == nil {
                setGlobalCmdVerify(false)
            }
            // Disable paging in both modes — file operations require
            // no paging even in classic mode.
            try await disablePaging(command: "//environment more false")
            try await disablePaging(command: "environment no more", pattern: "environment")
        }

        try await Task.sleep(nanoseconds: UInt64(selectDelayFactor(0.3) * 1_000_000_000))
        try await clearBuffer()
    }

    // MARK: Prompt Detection

    /// Detect the base prompt, stripping any ">..." navigation
    /// context and leading "*" — same logic as NokiaIsamSSH's
    /// equivalent method.
    /// Maps to netmiko's set_base_prompt() override.
    override public func setBasePrompt(
        primaryTerminator: String = "#",
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

        let capturePattern = #"\*?(.*?)(>.*)*#"#
        if let regex = try? NSRegularExpression(pattern: capturePattern) {
            let nsPrompt = basePrompt as NSString
            if let match = regex.firstMatch(
                in: basePrompt,
                range: NSRange(location: 0, length: nsPrompt.length)
            ), match.numberOfRanges > 1 {
                basePrompt = nsPrompt.substring(with: match.range(at: 1))
            }
        }
    }

    // MARK: Complete-on-Space (Model-Driven CLI Only)

    /// Disable command auto-completion on space — same rationale as
    /// CDOT CROS's identically-named method.
    /// Maps to netmiko's _disable_complete_on_space().
    @discardableResult
    private func disableCompleteOnSpace() async throws -> String {
        let delay = selectDelayFactor(0)
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        let command = "environment command-completion space false"
        try await writeChannel(normalizeCommand(command))
        try await Task.sleep(nanoseconds: UInt64(delay * 0.1 * 1_000_000_000))
        return try await readChannel()
    }

    // MARK: Enable Mode

    /// Enter SR OS administrative mode, using "enable" on model-driven
    /// CLI or "enable-admin" on classical CLI.
    /// Maps to netmiko's enable(cmd="enable", pattern="ssword",
    /// re_flags=re.IGNORECASE).
    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,

        defaultUsername: String = ""
    ) async throws -> String {
        let resolvedCommand = basePrompt.contains("@") ? command : "enable-admin"
        return try await super.enterEnableMode(
            secret: secret,
            command: resolvedCommand,
            pattern: pattern,
            enablePattern: enablePattern,
            checkState: checkState,
            caseInsensitive: caseInsensitive
        )
    }

    /// Check if in enable mode.
    ///
    /// Maps to netmiko's check_enable_mode(check_string="in admin
    /// mode").
    ///
    /// Genuinely unusual: this doesn't just READ the current state,
    /// it actively RE-SENDS the enable command every time it's
    /// called, then checks whether the resulting output contains
    /// "in admin mode". If a password prompt appears (meaning enable
    /// mode was NOT already active), it sends a bare return to pass
    /// through that prompt without actually authenticating, purely to
    /// drain the channel back to a clean state before returning
    /// false. This is a probe-by-re-attempting design, not a
    /// passive state check — worth flagging since every other
    /// isInEnableMode in this vendor set is a read-only query.
    override public func isInEnableMode(
        checkString: String = "in admin mode"
    ) async throws -> Bool {
        let command = basePrompt.contains("@") ? "enable" : "enable-admin"
        try await writeChannel(normalizeCommand(command))
        let output = try await readUntilPromptOrPattern(
            pattern: "ssword",
            readEntireLine: true
        )
        if output.contains("ssword") {
            // Send ENTER to pass the password prompt without
            // authenticating — this call is only probing state.
            try await writeChannel(profile.returnCharacter)
            _ = try await readUntilPrompt(readEntireLine: true)
        }
        return output.contains(checkString)
    }

    /// SR OS has no notion of exiting administrative mode once
    /// entered — hard no-op.
    /// Maps to netmiko's exit_enable_mode().
    @discardableResult
    override public func exitEnableMode(
        exitCommand: String = ""
    ) async throws -> String {
        return ""
    }

    // MARK: Config Mode

    /// Enter exclusive edit config mode — ONLY meaningful on
    /// model-driven CLI; a silent no-op on classical CLI.
    ///
    /// Maps to netmiko's config_mode(config_command="edit-config
    /// exclusive").
    @discardableResult
    override public func enterConfigMode(
        command: String = "edit-config exclusive",
        pattern: String = "",

        dotAll: Bool = false
    ) async throws -> String {
        var output = ""
        var resolvedPattern = pattern
        var dotAll = false

        if resolvedPattern.isEmpty {
            resolvedPattern = #"\(ex\)\[.*"# + basePrompt + #".*$"#
            dotAll = true
        }

        // Only model-driven CLI supports config mode at all.
        if basePrompt.contains("@") {
            output += try await super.enterConfigMode(
                command: command,
                pattern: resolvedPattern,
                dotAll: dotAll
            )
        }
        return output
    }

    /// Check config mode for Nokia SR OS.
    ///
    /// Maps to netmiko's check_config_mode(check_string="(ex)[",
    /// pattern="@").
    ///
    /// Classical CLI never has a real config mode — this returns
    /// false unconditionally in that case, without even attempting a
    /// channel read.
    override public func isInConfigMode(
        checkString: String = "(ex)[",
        pattern: String = "@"
    ) async throws -> Bool {
        guard basePrompt.contains("@") else {
            return false
        }
        return try await super.isInConfigMode(
            checkString: checkString,
            pattern: pattern
        )
    }

    /// Disable config edit-mode for Nokia SR OS.
    ///
    /// Maps to netmiko's exit_config_mode() — fully custom, no
    /// super() call.
    ///
    /// Always exits to the root context first via exitAll(). On
    /// model-driven CLI specifically, if that output shows we're
    /// still inside exclusive-edit context ("(ex)["), this checks for
    /// the asterisk marker indicating uncommitted changes and
    /// discards them with a warning before actually issuing
    /// "quit-config" to leave edit mode entirely. Finally verifies
    /// config mode was actually exited, throwing otherwise.
    @discardableResult
    override public func exitConfigMode(
        exitConfig: String = "",
        pattern: String = ""
    ) async throws -> String {
        var output = try await exitAll()

        if basePrompt.contains("@"), output.contains("(ex)[") {
            if output.contains("*(ex)[") {
                logger.warning("Uncommitted changes! Discarding changes!")
                output += try await discard()
            }

            let cmd = "quit-config"
            try await writeChannel(normalizeCommand(cmd))
            if cmdVerifyEnabled {
                output += try await readUntilPattern(
                    pattern: NSRegularExpression.escapedPattern(for: cmd)
                )
                output += try await readUntilPrompt(readEntireLine: true)
            } else {
                output += try await readUntilPrompt(readEntireLine: true)
            }
        }

        guard try await !isInConfigMode() else {
            throw SwiftmikoError.commandFailed("Failed to exit configuration mode")
        }
        return output
    }

    // MARK: Save Config

    /// Persist configuration to cflash.
    /// Maps to netmiko's save_config(cmd="/admin save").
    public func saveConfig(
        command: String = "/admin save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(command, expectString: "#")
    }

    // MARK: Config Set

    /// Maps to netmiko's send_config_set() — defaults exitConfigMode
    /// to false ONLY on model-driven CLI; classical CLI keeps the
    /// standard true default, since it has no persistent config-mode
    /// state to preserve across a command set anyway.
    @discardableResult
    override public func sendConfigSet(
        _ commands: [String],
        exitConfigMode: Bool = true,
        readTimeout: TimeInterval? = nil,
        maxLoops: Int? = nil,
        stripPrompt: Bool = false,
        stripCommand: Bool = false,
        configModeCommand: String? = nil,
        cmdVerify: Bool = true,
        enterConfigMode: Bool = true,
        errorPattern: String = "",
        terminator: String = "#",
        bypassCommands: String? = nil
    ) async throws -> String {
        let resolvedExit = basePrompt.contains("@") ? false : exitConfigMode
        return try await super.sendConfigSet(commands, exitConfigMode: resolvedExit)
    }

    // MARK: Commit

    /// Activate changes from the private candidate configuration.
    ///
    /// Maps to netmiko's commit() — exits to root context first via
    /// exitAll(), then only actually sends "commit" if uncommitted
    /// changes are detected in that output (the "*(ex)[" marker,
    /// same signal used by exitConfigMode()).
    @discardableResult
    public func commit() async throws -> String {
        var output = try await exitAll()

        if basePrompt.contains("@"), output.contains("*(ex)[") {
            logger.info("Apply uncommitted changes!")
            let cmd = "commit"
            try await writeChannel(normalizeCommand(cmd))
            var newOutput = ""
            if cmdVerifyEnabled {
                newOutput += try await readUntilPattern(
                    pattern: NSRegularExpression.escapedPattern(for: cmd)
                )
            }
            if !newOutput.contains("@") {
                newOutput += try await readUntilPattern(pattern: "@")
            }
            output += newOutput
        }
        return output
    }

    // MARK: Internal Helpers

    /// Return to the root context.
    /// Maps to netmiko's _exit_all().
    private func exitAll() async throws -> String {
        var output = ""
        let exitCommand = "exit all"
        try await writeChannel(normalizeCommand(exitCommand))

        if cmdVerifyEnabled {
            output += try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(for: exitCommand)
            )
            output += try await readUntilPrompt(readEntireLine: true)
        } else {
            output += try await readUntilPrompt(readEntireLine: true)
        }
        return output
    }

    /// Discard changes from the private candidate configuration.
    /// Maps to netmiko's _discard(). Only actually does anything on
    /// model-driven CLI; a silent no-op otherwise.
    private func discard() async throws -> String {
        var output = ""
        guard basePrompt.contains("@") else { return output }

        let cmd = "discard"
        try await writeChannel(normalizeCommand(cmd))
        var newOutput = ""
        if cmdVerifyEnabled {
            newOutput += try await readUntilPattern(
                pattern: NSRegularExpression.escapedPattern(for: cmd)
            )
        }
        if !newOutput.contains("@") {
            newOutput += try await readUntilPrompt(readEntireLine: true)
        }
        output += newOutput
        return output
    }

    // MARK: Output Stripping

    /// Strip the prompt, additionally removing Nokia's context prompt
    /// line on model-driven CLI.
    ///
    /// Maps to netmiko's strip_prompt() override.
    ///
    /// `nokiaContextFilter` is referenced here as a standalone
    /// utility function — matching Netmiko's own
    /// netmiko.utilities.nokia_context_filter import. That function's
    /// implementation isn't shown in this file, so it's declared here
    /// as an assumed dependency; worth locating and translating that
    /// utility function specifically if it hasn't been done already.
    override public func stripPrompt(_ output: String) -> String {
        let base = super.stripPrompt(output)

        guard basePrompt.contains("@") else { return base }

        var lines = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        guard var lastLine = lines.last else { return base }
        lines.removeLast()

        lastLine = nokiaContextFilter(lastLine)
        lines.append(lastLine)

        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Cleanup

    /// Gracefully exit the SSH session.
    ///
    /// Maps to netmiko's cleanup(command="logout").
    ///
    /// Netmiko's own comment explains a subtlety: passing an empty
    /// pattern to isInConfigMode() forces the underlying
    /// implementation down a timing-based path rather than a
    /// pattern-matching one — presumably safer during teardown when
    /// the exact channel state is less predictable.
    override public func cleanup(command: String = "logout") async throws {
        do {
            if try await isInConfigMode(pattern: "") {
                _ = try await exitConfigMode()
            }
        } catch {
            // Best-effort — swallow any failure here.
        }
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }
}

// MARK: - NokiaSrosSSH

/// Nokia SR OS SSH driver — no differences from the base.
/// Maps to netmiko's NokiaSrosSSH(NokiaSros).
public final class NokiaSrosSSH: NokiaSros {}

// MARK: - NokiaSrosTelnet

/// Nokia SR OS Telnet driver — no differences from the base.
/// Maps to netmiko's NokiaSrosTelnet(NokiaSros).
public final class NokiaSrosTelnet: NokiaSros {}

// MARK: - NokiaSrosFileTransfer

/// Nokia SR OS SCP File Transfer driver.
///
/// Maps to netmiko's NokiaSrosFileTransfer(BaseFileTransfer).
///
/// Like the connection driver itself, file-listing commands differ
/// between CLI dialects — "file list" on model-driven CLI, "file dir"
/// on classical CLI. No MD5 support at all, same pattern as Aruba OS,
/// EXOS, and MikroTik RouterOS.
public final class NokiaSrosFileTransfer: SCPHandler {

    /// Typed reference to the owning connection, needed to check its
    /// basePrompt for the CLI-dialect branch.
    private var nokiaConnection: NokiaSros {
        connection as! NokiaSros
    }

    /// Maps to netmiko's __init__, with hash_supported defaulting to
    /// false.
    public init(
        connection: NokiaSros,
        sourceFile: String,
        destinationFile: String,
        fileSystem: String? = nil,
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

    /// The file-listing command, which differs by CLI dialect.
    /// Maps to netmiko's _file_list_command().
    private func fileListCommand() async -> String {
        let basePrompt = nokiaConnection.basePrompt
        return basePrompt.contains("@") ? "file list " : "file dir "
    }

    // MARK: Space Available

    /// Maps to netmiko's remote_space_available(search_pattern=
    /// r"(\d+)\s+\w+\s+free").
    override public func remoteSpaceAvailable(
        searchPattern: String = #"(\d+)\s+\w+\s+free"#
    ) async throws -> Int {
        let command = await fileListCommand() + fileSystem
        let output = try await connection.sendCommand(command)

        guard let match = output.range(of: searchPattern, options: .regularExpression) else {
            throw SwiftmikoError.commandFailed(
                "pattern: \(searchPattern) not detected in output:\n\n\(output)"
            )
        }

        let regex = try? NSRegularExpression(pattern: searchPattern)
        let nsOutput = output as NSString
        guard let regexMatch = regex?.firstMatch(
            in: output, range: NSRange(location: 0, length: nsOutput.length)
        ), regexMatch.numberOfRanges > 1,
        let value = Int(nsOutput.substring(with: regexMatch.range(at: 1))) else {
            throw SwiftmikoError.commandFailed("Unable to parse space-available output")
        }
        _ = match
        return value
    }

    // MARK: File Existence

    /// Maps to netmiko's check_file_exists().
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        switch direction {
        case .put:
            let command = remoteCommand.isEmpty
                ? await fileListCommand() + "\(fileSystem)/\(destinationFile)"
                : remoteCommand
            let destFileName = (destinationFile.replacingOccurrences(of: "\\", with: "/") as NSString)
                .lastPathComponent
            let output = try await connection.sendCommand(command)

            if output.contains("File Not Found") {
                return false
            } else if output.contains(destFileName) {
                return true
            } else {
                throw SwiftmikoError.commandFailed("Unexpected output from check_file_exists")
            }
        case .get:
            return FileManager.default.fileExists(atPath: destinationFile)
        }
    }

    // MARK: File Size

    /// Maps to netmiko's remote_file_size().
    ///
    /// Parses a fixed-width directory listing:
    ///     10/16/2019  10:00p                6738 {filename}
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
            ? await fileListCommand() + "\(fileSystem)/\(targetFile)"
            : remoteCommand
        let output = try await connection.sendCommand(command)

        guard !output.contains("File Not Found"), !output.contains("Invalid element value") else {
            throw SwiftmikoError.commandFailed("Unable to find file on remote system")
        }

        let destFileName = (targetFile.replacingOccurrences(of: "\\", with: "/") as NSString)
            .lastPathComponent
        let escapedName = NSRegularExpression.escapedPattern(for: destFileName)
        let pattern = "\\S+\\s+\\S+\\s+(\\d+)\\s+\(escapedName)"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw SwiftmikoError.commandFailed("Filename entry not found in dir output")
        }
        let nsOutput = output as NSString
        guard let match = regex.firstMatch(
            in: output, range: NSRange(location: 0, length: nsOutput.length)
        ), match.numberOfRanges > 1,
        let size = Int(nsOutput.substring(with: match.range(at: 1))) else {
            throw SwiftmikoError.commandFailed("Filename entry not found in dir output")
        }
        return size
    }

    // MARK: Verification

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

    // MARK: MD5 — Unsupported

    public func fileMD5(fileName: String, addNewline: Bool = false) throws -> String {
        throw SwiftmikoError.notImplemented("SR-OS does not support an MD5-hash operation.")
    }
    override public func compareMD5() async throws -> Bool {
        throw SwiftmikoError.notImplemented("SR-OS does not support an MD5-hash operation.")
    }
    override public func remoteMD5(baseCommand: String = "", remoteFile: String? = nil) async throws -> String {
        throw SwiftmikoError.notImplemented("SR-OS does not support an MD5-hash operation.")
    }
}
