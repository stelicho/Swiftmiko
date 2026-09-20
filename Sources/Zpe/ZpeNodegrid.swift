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
// Sources/Swiftmiko/Zpe/ZpeNodegrid.swift

import Foundation

/// ZPE Systems Nodegrid SSH driver.
///
/// Maps to netmiko's ZpeNodegridSSH(NoEnable, NoConfig, LinuxSSH).
///
/// The Nodegrid OS represents configuration as a directory-style tree
/// rather than the enable/config-mode model most Cisco-derived drivers
/// use. Navigation is `cd`/`ls`; reads are `show`; writes are
/// `set param=value`. Changes are staged in place and indicated by a
/// '+' prefix in the prompt until `commit` is run. There is no
/// traditional enable or config mode — hence NoEnable + NoConfig.
///
/// Prompt examples:
///     [admin@nodegrid /]#           No staged changes
///     [+admin@nodegrid ETH0]#       Staged changes pending commit
///
/// A separate Linux Bash shell is reachable via `shell`; `exit`
/// returns to the Nodegrid CLI. That shell has its own prompt shape
/// entirely unlike the Nodegrid one — see shellPromptPattern below.
public final class ZpeNodegridSSH: LinuxSSHConnection, NoEnable, NoConfig {

    // MARK: Prompt Patterns

    /// Matches both staged and unstaged Nodegrid prompts:
    /// [admin@nodegrid /]#  and  [+admin@nodegrid ETH0]#
    override public nonisolated var promptPattern: String {
        #"\[\+?.*\]#"#
    }

    /// Matches the underlying Bash shell prompt, e.g.
    /// root@nodegrid:/var/home#  or  admin@nodegrid:~$
    /// Exposed as `internal` rather than `private` because
    /// ZpeNodegridFileTransfer needs it to detect shell-mode output.
    internal nonisolated var shellPromptPattern: String {
        #".+@.+:.+[\$#]"#
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self.ansi_escape_codes = True
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt()
    ///     self.disable_paging()
    override public func sessionPreparation() async throws {
        ansiEscapeCodes = true
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
        try await disablePaging()
    }

    // MARK: Prompt Detection

    /// Detect the base prompt using the Nodegrid bracket pattern rather
    /// than the standard [>#] terminators most drivers rely on.
    ///
    /// Maps to netmiko's set_base_prompt(), which defaults `pattern`
    /// to `self.prompt_pattern` when the caller doesn't supply one.
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = "",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern ?? promptPattern
        )
    }

    /// Find the current prompt, defaulting to the Nodegrid bracket
    /// pattern rather than a generic search.
    ///
    /// Maps to netmiko's find_prompt().
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.findPrompt(
            delay: delay,
            pattern: pattern ?? promptPattern
        )
    }

    /// The regex used by sendCommand to detect output termination.
    ///
    /// Maps to netmiko's _prompt_handler(auto_find_prompt).
    ///
    /// Deliberately returns the broad promptPattern rather than the
    /// escaped literal basePrompt — because `cd` changes the visible
    /// path segment of the prompt (e.g. "/" becomes "ETH0"), an exact
    /// match against the originally detected basePrompt would stop
    /// matching the moment the user navigates anywhere.
    override public func promptHandler(autoFindPrompt: Bool) async -> String {
        return promptPattern
    }

    // MARK: Output Stripping

    /// Strip the trailing Nodegrid prompt from command output.
    ///
    /// Maps to netmiko's strip_prompt().
    ///
    /// Uses the regex pattern rather than an exact basePrompt string
    /// match for the same reason as promptHandler above — directory
    /// navigation and the '+' staged-change indicator both alter the
    /// visible prompt text without changing what should be stripped.
    override public func stripPrompt(_ output: String) -> String {
        var lines = output.components(separatedBy: responseReturn)
        guard let last = lines.last else { return output }
        if last.range(of: promptPattern, options: .regularExpression) != nil {
            lines.removeLast()
            return lines.joined(separator: responseReturn)
        }
        return output
    }

    // MARK: Paging

    /// Disable paging for the current CLI session.
    ///
    /// WARNING: Not officially documented by ZPE — carried over
    /// verbatim from Netmiko's own warning. Could negatively impact
    /// performance if ZPE changes this behavior in a future release.
    ///
    /// Maps to netmiko's disable_paging(command=".sessionpageout undefined=no").
    @discardableResult
    override public func disablePaging(
        command: String = ".sessionpageout undefined=no",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        return try await sendCommand(
            command,
            expectString: pattern ?? promptPattern
        )
    }

    // MARK: Commit

    /// Commit staged configuration changes.
    ///
    /// This is Nodegrid's equivalent of a config-mode "write" — the
    /// only way pending '+' prefixed changes actually take effect.
    /// Maps to netmiko's commit().
    @discardableResult
    public func commit() async throws -> String {
        return try await sendCommand(
            "commit",
            readTimeout: 30,
            expectString: promptPattern
        )
    }

    // MARK: Shell Mode

    /// Enter the underlying Bash shell.
    /// Maps to netmiko's _enter_shell().
    /// Internal rather than private — ZpeNodegridFileTransfer calls
    /// this directly to run md5sum outside the Nodegrid tree CLI.
    @discardableResult
    override internal func enterShell() async throws -> String {
        return try await sendCommand(
            "shell",
            expectString: shellPromptPattern
        )
    }

    /// Return to the Nodegrid CLI from the Bash shell.
    /// Maps to netmiko's _return_cli().
    @discardableResult
    override internal func returnCLI() async throws -> String {
        return try await sendCommand(
            "exit",
            expectString: promptPattern
        )
    }
}

// MARK: - ZpeNodegridFileTransfer

/// ZPE Nodegrid SCP File Transfer driver.
///
/// Maps to netmiko's ZpeNodegridFileTransfer(BaseFileTransfer).
///
/// Note the base type here is the generic SCPHandler, not a
/// Cisco-flavored file transfer class — Nodegrid's transfer commands
/// are standard Unix (md5sum, ls, df) rather than IOS-style "dir" and
/// "verify /md5", so it uses the Unix-oriented helpers.
public final class ZpeNodegridFileTransfer: SCPHandler {

    /// Typed reference back to the owning connection, giving access to
    /// Nodegrid-specific members (shellPromptPattern, enterShell,
    /// returnCLI) that a plain BaseConnection reference wouldn't expose.
    ///
    /// Maps to netmiko's class-level type annotation:
    ///     ssh_ctl_chan: "ZpeNodegridSSH"
    private var nodegridConnection: ZpeNodegridSSH {
        // Safe to force-cast: this class is only ever constructed with
        // a ZpeNodegridSSH connection via the initializer below.
        connection as! ZpeNodegridSSH
    }

    /// Maps to netmiko's __init__, which just forwards to the parent
    /// with file_system defaulted to "/var/tmp" instead of the
    /// generic BaseFileTransfer default.
    public init(
        connection: ZpeNodegridSSH,
        sourceFile: String,
        destFile: String,
        fileSystem: String = "/var/tmp",
        direction: SCPTransferDirection = .put
    ) async throws {
        try await super.init(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destFile,
            fileSystem: fileSystem,
            direction: direction
        )
    }

    // MARK: Space / Existence Checks

    /// Return space available on the remote device.
    ///
    /// Maps to netmiko's remote_space_available(), which overrides the
    /// search_pattern argument with the shell prompt before delegating
    /// to the generic Unix implementation — because `df` and friends
    /// are run inside the Bash shell, not the Nodegrid tree CLI.
    override public func remoteSpaceAvailable(
        searchPattern: String = ""
    ) async throws -> Int {
        return try await remoteSpaceAvailableUnix(
            searchPattern: nodegridConnection.shellPromptPattern
        )
    }

    /// Check if the destination file already exists.
    /// Maps to netmiko's check_file_exists().
    override public func checkFileExists(
        remoteCommand: String = ""
    ) async throws -> Bool {
        return try await checkFileExistsUnix(
            remoteCommand: remoteCommand,
            searchPattern: nodegridConnection.shellPromptPattern
        )
    }

    /// Get the file size of the remote file.
    /// Maps to netmiko's remote_file_size().
    override public func remoteFileSize(
        remoteCommand: String = "",
        remoteFile: String? = nil
    ) async throws -> Int {
        return try await remoteFileSizeUnix(
            remoteCommand: remoteCommand,
            remoteFile: remoteFile,
            searchPattern: nodegridConnection.shellPromptPattern
        )
    }

    // MARK: MD5

    /// Calculate the remote MD5 hash.
    ///
    /// Maps to netmiko's remote_md5().
    ///
    /// Unlike a typical Cisco device where "verify /md5" runs directly
    /// at the normal CLI prompt, Nodegrid has no such command in its
    /// tree CLI — md5sum only exists in the underlying Bash shell.
    /// This method drops into the shell, runs the command, and
    /// guarantees it returns to the CLI even if the command fails —
    /// mirroring Python's try/finally with a Swift defer.
    override public func remoteMD5(
        baseCommand: String = "md5sum",
        remoteFile: String? = nil
    ) async throws -> String {
        let targetFile: String
        if let remoteFile {
            targetFile = remoteFile
        } else {
            switch direction {
            case .put: targetFile = destinationFile
            case .get: targetFile = sourceFile
            }
        }

        let remoteCommand = "\(baseCommand) \(fileSystem)/\(targetFile)"

        try await nodegridConnection.enterShell()
        defer {
            // Best-effort return to CLI — mirrors Python's `finally`.
            // If this fails, the connection is left in shell mode,
            // which the caller's next command will surface clearly.
            Task { try? await nodegridConnection.returnCLI() }
        }

        let output = try await nodegridConnection.sendCommand(
            remoteCommand,
            readTimeout: 300,
            expectString: nodegridConnection.shellPromptPattern
        )

        return try Self.processMD5(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Extract the MD5 hash from raw md5sum output.
    ///
    /// Standard md5sum output is "<hash>  <filename>" — the pattern
    /// captures everything up to the first run of whitespace.
    /// Maps to netmiko's static process_md5().
    static func processMD5(_ output: String) throws -> String {
        guard let match = output.range(of: #"^\S+"#, options: .regularExpression) else {
            throw SwiftmikoError.commandFailed("Invalid output from MD5 command: \(output)")
        }
        let matchedText = String(output[match])
        let hash = matchedText.trimmingCharacters(in: .whitespaces)
        return hash
    }

    // MARK: Unsupported Operations

    override public func enableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented(
            "ZPE Nodegrid does not support enableSCP"
        )
    }

    override public func disableSCP(command: String = "") async throws {
        throw SwiftmikoError.notImplemented(
            "ZPE Nodegrid does not support disableSCP"
        )
    }
}
