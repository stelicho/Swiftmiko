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
//  BaseConnection.swift
//  Swiftmiko
//
//  Transport-neutral equivalent of netmiko/base_connection.py.
//
//  REWORK NOTES (this pass):
//  This revision folds in the highest-frequency gaps surfaced across
//  the full vendor-driver translation pass — the items that came up
//  in five, six, sometimes ten separate driver files rather than
//  one-offs. It does NOT attempt to close every backlog item; see the
//  "Deferred" list at the bottom of this file for what's intentionally
//  left for a future pass, and why.
//

import Foundation

// MARK: - Connection profile

public struct ConnectionProfile: Sendable {
    public var host: String
    public var port: Int
    public var deviceType: String
    public var username: String
    public var auth: AuthMethod
    public var secret: String?

    public var connectionTimeout: TimeInterval
    public var authTimeout: TimeInterval
    public var bannerTimeout: TimeInterval
    public var readTimeout: TimeInterval
    public var sessionTimeout: TimeInterval

    public var fastCli: Bool
    public var strictHostKeyChecking: Bool
    public var allowAutoChange: Bool
    public var keepaliveInterval: Int

    public var returnCharacter: String
    public var responseReturnCharacter: String

    /// Maps to Netmiko's global_delay_factor — a multiplier applied to
    /// every internal settle-delay a driver requests via
    /// selectDelayFactor(_:). Surfaced repeatedly across ~10+ drivers
    /// as `time.sleep(0.3 * self.global_delay_factor)`, which every
    /// prior translation pass silently hardcoded to a flat sleep,
    /// dropping this scaling entirely. This restores it as a real,
    /// per-connection setting.
    public var globalDelayFactor: Double

    /// Maps to Netmiko's global_cmd_verify. `nil` means "defer to the
    /// per-call default" (true); an explicit value overrides that for
    /// every call on this connection until changed again. Needed by
    /// Comware, Silver Peak, Casa CMTS, Nokia SR OS, and others.
    public var globalCmdVerify: Bool?

    /// SSH key-exchange algorithms to allow, overriding the
    /// transport's own defaults. Needed by Fortinet.
    public var allowedKeyExchangeAlgorithms: Set<String>?

    /// SSH public-key algorithms to disallow. Needed by HP ProCurve.
    public var disabledPublicKeyAlgorithms: Set<String>?

    /// Serial port settings for `_serial` device types. `nil` uses
    /// SerialSettings.default (9600 8N1). Ignored for SSH/Telnet.
    public var serialSettings: SerialSettings?

    /// Opt-in fallback to legacy AES-CBC ciphers (see
    /// LegacyCBCTransportProtection.swift) for SSH servers too old to
    /// offer AES-GCM — e.g. classic Cisco C7200 IOS images. CBC-mode SSH
    /// ciphers have known weaknesses, so this defaults to `false` and
    /// should only be set for lab/EOL gear you control.
    public var allowLegacyCiphers: Bool

    public init(
        host: String,
        port: Int = 22,
        deviceType: String,
        username: String,
        auth: AuthMethod,
        secret: String? = nil,
        connectionTimeout: TimeInterval = 10,
        authTimeout: TimeInterval = 15,
        bannerTimeout: TimeInterval = 15,
        readTimeout: TimeInterval = 30,
        sessionTimeout: TimeInterval = 60,
        fastCli: Bool = true,
        strictHostKeyChecking: Bool = false,
        allowAutoChange: Bool = false,
        keepaliveInterval: Int = 0,
        returnCharacter: String = "\n",
        responseReturnCharacter: String = "\n",
        globalDelayFactor: Double = 1.0,
        globalCmdVerify: Bool? = nil,
        allowedKeyExchangeAlgorithms: Set<String>? = nil,
        disabledPublicKeyAlgorithms: Set<String>? = nil,
        serialSettings: SerialSettings? = nil,
        allowLegacyCiphers: Bool = false
    ) {
        self.host = host
        self.port = port
        self.deviceType = deviceType
        self.username = username
        self.auth = auth
        self.secret = secret
        self.connectionTimeout = connectionTimeout
        self.authTimeout = authTimeout
        self.bannerTimeout = bannerTimeout
        self.readTimeout = readTimeout
        self.sessionTimeout = sessionTimeout
        self.fastCli = fastCli
        self.strictHostKeyChecking = strictHostKeyChecking
        self.allowAutoChange = allowAutoChange
        self.keepaliveInterval = keepaliveInterval
        self.returnCharacter = returnCharacter
        self.responseReturnCharacter = responseReturnCharacter
        self.globalDelayFactor = globalDelayFactor
        self.globalCmdVerify = globalCmdVerify
        self.allowedKeyExchangeAlgorithms = allowedKeyExchangeAlgorithms
        self.disabledPublicKeyAlgorithms = disabledPublicKeyAlgorithms
        self.serialSettings = serialSettings
        self.allowLegacyCiphers = allowLegacyCiphers
    }

    public var passwordString: String? {
        switch auth {
        case .password(let password):
            return password
        case .keyFile, .sshAgent, .none:
            return nil
        }
    }
}

public struct SessionLogConfig: Sendable {
    public var filePath: String
    public var mode: SessionLogMode
    public var recordWrites: Bool

    public init(
        filePath: String,
        mode: SessionLogMode = .write,
        recordWrites: Bool = false
    ) {
        self.filePath = filePath
        self.mode = mode
        self.recordWrites = recordWrites
    }
}

// MARK: - Minimal logging

public struct SwiftmikoLogger: Sendable {
    public let label: String
    public var enabled: Bool

    public init(label: String, enabled: Bool = true) {
        self.label = label
        self.enabled = enabled
    }

    public func trace(_ message: String) { emit("TRACE", message) }
    public func debug(_ message: String) { emit("DEBUG", message) }
    public func info(_ message: String) { emit("INFO", message) }
    public func warning(_ message: String) { emit("WARNING", message) }

    private func emit(_ level: String, _ message: String) {
        guard enabled else { return }
        print("[\(level)] \(label): \(message)")
    }
}

public typealias ChannelProvider = @Sendable (
    _ profile: ConnectionProfile
) async throws -> any Channel

public protocol DeviceDriver: AnyObject {
    func sessionPreparation() async throws
    var promptPattern: String { get }
    var supportsConfigMode: Bool { get }
}

// MARK: - Base connection

open class BaseConnection: DeviceDriver {
    public let profile: ConnectionProfile
    public internal(set) var basePrompt = ""

    internal let logger: SwiftmikoLogger
    internal private(set) var channel: (any Channel)?
    private let channelProvider: ChannelProvider?
    private var readBuffer = ""

    /// Was `private`; several drivers (F5 TMSH, Pluribus) need to
    /// correct this directly rather than only through
    /// enterConfigMode()/exitConfigMode().
    internal var inConfigMode = false

    /// Was `private`; several drivers (Teldat, Audiocode, Check Point
    /// Gaia, Juniper, Ericsson MiniLink, F5 TMSH, Nokia ISAM) need to
    /// set `.fin` directly during cleanup().
    internal var sessionLog: SessionLog?
    private let sessionLogConfig: SessionLogConfig?
    private let recordWrites: Bool

    /// Was a fixed computed `false`; every driver needing ANSI
    /// handling (NX-OS, S200, S300, Zyxel, ZPE, Arista, Adtran,
    /// dozens more) needs to actually set this to true during
    /// session prep.
    public var ansiEscapeCodes: Bool = false

    /// Was entirely absent. Confirmed needed by Silver Peak, Casa
    /// CMTS, HP Comware, Nokia SR OS. `nil` defers to the per-call
    /// default (true).
    public private(set) var globalCmdVerify: Bool?

    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        logLabel: String = "swiftmiko",
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil,
        globalCmdVerify: Bool? = nil
    ) {
        self.profile = profile
        self.sessionLogConfig = sessionLog
        self.recordWrites = sessionLog?.recordWrites ?? false
        self.logger = SwiftmikoLogger(label: logLabel, enabled: loggerEnabled)
        self.channel = channel
        self.channelProvider = channelProvider
        self.globalCmdVerify = globalCmdVerify ?? profile.globalCmdVerify

        if let sessionLog {
            self.sessionLog = SessionLog(
                fileName: sessionLog.filePath,
                fileMode: sessionLog.mode,
                noLog: Self.secretFilterValues(for: profile)
            )
        } else {
            self.sessionLog = nil
        }
    }

    private static func secretFilterValues(
        for profile: ConnectionProfile
    ) -> [String: String] {
        var values: [String: String] = [:]
        if let password = profile.passwordString, !password.isEmpty {
            values["password"] = password
        }
        if let secret = profile.secret, !secret.isEmpty {
            values["secret"] = secret
        }
        return values
    }

    /// Set globalCmdVerify from within the actor. Confirmed needed by
    /// Silver Peak (post-init), Casa CMTS (temporary suspend/restore
    /// around a raw control character), HP Comware, Nokia SR OS.
    public func setGlobalCmdVerify(_ value: Bool?) {
        globalCmdVerify = value
    }

    /// Resolved value most call sites should read — true unless
    /// explicitly turned off.
    public var cmdVerifyEnabled: Bool { globalCmdVerify ?? true }

    // MARK: Lifecycle

    public func connect() async throws {
        logger.info("Connecting to \(profile.host):\(profile.port)")

        if let sessionLog { try sessionLog.open() }

        if channel == nil {
            guard let channelProvider else {
                throw SwiftmikoError.connectionFailed(
                    "No channel or channel provider was supplied"
                )
            }
            channel = try await channelProvider(profile)
        }

        guard let channel else { throw SwiftmikoError.noConnection }
        if !channel.isOpen { try await channel.open() }
        try await authenticate()
        try await sessionPreparation()
        logger.info("Connection established to \(profile.host)")
    }

    public func disconnect() async {
        logger.info("Disconnecting from \(profile.host)")
        await channel?.close()
        resetSessionState()
    }

    /// Maps to netmiko's `self.remote_conn.close()` — an abrupt,
    /// non-cooperative teardown used when a session is known to be
    /// bad (e.g. an authentication-failure banner appeared in the
    /// channel text itself, as on Fiberstore FSOS, Keymile NOS, and
    /// Huawei ONT Telnet). Unlike disconnect(), this makes no attempt
    /// to run any graceful logout sequence — the connection is
    /// assumed already broken.
    public func closeTransport() async {
        await channel?.close()
        resetSessionState()
    }

    private func resetSessionState() {
        channel = nil
        readBuffer = ""
        basePrompt = ""
        inConfigMode = false
        try? sessionLog?.close()
    }

    /// Confirmed needed by Huawei SmartAX's cleanup() polling loop.
    public func isAlive() async -> Bool {
        channel?.isOpen ?? false
    }

    private func authenticate() async throws {
        guard let channel else { throw SwiftmikoError.noConnection }
        do {
            try await channel.authenticate(username: profile.username, using: profile.auth)
        } catch {
            throw SwiftmikoError.authenticationFailed(
                "Authentication failed for \(profile.username)@\(profile.host): \(error)"
            )
        }
    }

    // MARK: Channel I/O

    public func writeChannel(_ data: String) async throws {
        guard let channel, channel.isOpen else { throw SwiftmikoError.noConnection }
        if recordWrites { sessionLog?.write(data) }
        try await channel.write(data)
        logger.trace("WRITE: \(data.debugDescription)")
    }

    public func readChannel() async throws -> String {
        guard let channel, channel.isOpen else { throw SwiftmikoError.noConnection }
        let raw = try await channel.readAvailable()
        let result = normalizeOutput(raw)
        sessionLog?.write(result)
        logger.trace("READ: \(result.debugDescription)")
        return result
    }

    /// Fixed-delay read with no pattern matching at all — distinct
    /// from readUntilPrompt/readUntilPattern. Confirmed needed by
    /// A10 (unstable prompt shapes on unlicensed devices).
    public func readChannelTiming(readTimeout: TimeInterval = 10.0) async throws -> String {
        let deadline = Date().addingTimeInterval(readTimeout)
        var accumulated = ""
        while Date() < deadline {
            accumulated += try await readChannel()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return accumulated
    }

    public func readUntilPrompt(
        timeout: TimeInterval? = nil,
        readEntireLine: Bool = false
    ) async throws -> String {
        try await readUntilPromptOrPattern(
            pattern: promptPattern,
            timeout: timeout,
            readEntireLine: readEntireLine
        )
    }

    public func readUntilPromptOrPattern(
        pattern: String,
        timeout: TimeInterval? = nil,
        readEntireLine: Bool = false,
        caseInsensitive: Bool = false
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout ?? profile.readTimeout)
        var accumulated = ""
        let options: String.CompareOptions = caseInsensitive
            ? [.regularExpression, .caseInsensitive] : [.regularExpression]

        while Date() < deadline {
            let chunk = try await readChannel()
            if chunk.isEmpty {
                // Nothing buffered yet — avoid a tight busy-loop hammering
                // the channel and flooding trace logs while waiting for
                // the device to respond.
                try await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            accumulated += chunk

            let matchesPrompt = accumulated.range(of: promptPattern, options: options) != nil
            let matchesPattern = accumulated.range(of: pattern, options: options) != nil

            if matchesPrompt || matchesPattern {
                // readEntireLine: keep reading until the match is on
                // its own trailing line (not mid-line), matching
                // Netmiko's read_entire_line semantics used by
                // Yamaha, Genexis, Adtran, Garderos and others.
                if readEntireLine,
                   let lastLine = accumulated.components(separatedBy: .newlines).last,
                   lastLine.range(of: pattern, options: options) == nil,
                   lastLine.range(of: promptPattern, options: options) == nil {
                    continue
                }
                return accumulated
            }
        }
        throw SwiftmikoError.timeout("Timed out waiting for response on \(profile.host)")
    }

    public func readUntilPattern(
        pattern: String,
        timeout: TimeInterval? = nil,
        caseInsensitive: Bool = false
    ) async throws -> String {
        try await readUntilPromptOrPattern(
            pattern: pattern,
            timeout: timeout,
            caseInsensitive: caseInsensitive
        )
    }

    /// Now returns the read data, and takes a `count:` parameter —
    /// confirmed needed by Keymile NOS, which overrides this method's
    /// BEHAVIOR (auth-failure detection), not just its arguments.
    @discardableResult
    open func testChannelRead(
        count: Int = 0,
        pattern: String = ""
    ) async throws -> String {
        if pattern.isEmpty {
            return try await readChannelTiming(readTimeout: 2.0)
        }
        return try await readUntilPromptOrPattern(pattern: pattern)
    }

    // MARK: Commands

    @discardableResult
    open func sendCommand(
        _ command: String,
        readTimeout: TimeInterval? = nil,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true,
        autoFindPrompt: Bool = true
    ) async throws -> String {
        try await writeChannel(command + profile.returnCharacter)
        var output: String
        if let expectString {
            output = try await readUntilPromptOrPattern(pattern: expectString, timeout: readTimeout)
        } else {
            output = try await readUntilPrompt(timeout: readTimeout)
        }
        if stripCommand { output = self.stripCommand(command, output: output) }
        if stripPrompt { output = self.stripPrompt(output) }
        return output
    }

    /// Timing-based send — no prompt/pattern detection at all, just a
    /// fixed wait. Confirmed needed by Alaxala, Fortinet, Ericsson,
    /// Genexis, MikroTik, and many others.
    @discardableResult
    open func sendCommandTiming(
        _ command: String,
        readTimeout: TimeInterval = 2.0,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true
    ) async throws -> String {
        try await writeChannel(command + profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(readTimeout * 1_000_000_000))
        var output = try await readChannel()
        if stripCommand { output = self.stripCommand(command, output: output) }
        if stripPrompt { output = self.stripPrompt(output) }
        return output
    }

    /// Send several commands, each waiting for the SAME shared expect
    /// string — distinct from sendConfigSet (no config-mode
    /// assumption). Confirmed needed by Fortinet.
    @discardableResult
    open func sendMultiline(
        _ commands: [String],
        expectString: String
    ) async throws -> String {
        var output = ""
        for command in commands {
            output += try await sendCommand(
                command,
                expectString: expectString,
                stripPrompt: false,
                stripCommand: false
            )
        }
        return output
    }

    /// Now the FULL signature — the two-parameter stub was
    /// discovered to be inadequate as early as Adva F3, and every
    /// driver since has needed some subset of this.
    @discardableResult
    open func sendConfigSet(
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
        guard supportsConfigMode else {
            throw SwiftmikoError.configModeNotSupported
        }
        var output = ""
        if enterConfigMode {
            if let configModeCommand {
                output += try await self.enterConfigMode(command: configModeCommand)
            } else {
                output += try await self.enterConfigMode()
            }
        }
        for command in commands {
            output += try await sendCommand(
                command,
                readTimeout: readTimeout,
                stripPrompt: stripPrompt,
                stripCommand: stripCommand,
                cmdVerify: cmdVerify
            )
            if !errorPattern.isEmpty,
               output.range(of: errorPattern, options: .regularExpression) != nil {
                throw SwiftmikoError.commandFailed(
                    "Config command failed matching errorPattern:\n\n\(output)"
                )
            }
        }
        if exitConfigMode {
            output += try await self.exitConfigMode()
        }
        return output
    }

    // MARK: Prompt and mode defaults

    public nonisolated var promptPattern: String { "[>#]" }
    public nonisolated var supportsConfigMode: Bool { true }

    /// Full signature — confirmed needed by nearly every driver in
    /// this pass (previously took no parameters at all).
    open func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        let searchPattern = pattern ?? "[\(primaryTerminator)\(altTerminator)]"
        let output = try await readUntilPattern(pattern: searchPattern)
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let prompt = lines.last else {
            throw SwiftmikoError.unexpectedPrompt("Could not detect prompt on \(profile.host)")
        }
        basePrompt = prompt
        logger.debug("Base prompt detected: '\(basePrompt)'")
    }

    open func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        try await writeChannel(profile.returnCharacter)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        let output = try await readChannel()
        if let pattern, !pattern.isEmpty {
            // Best-effort: return whatever line matches, falling back
            // to the last non-empty line.
            let lines = output.components(separatedBy: .newlines)
            if let matched = lines.last(where: {
                $0.range(of: pattern, options: .regularExpression) != nil
            }) {
                return matched.trimmingCharacters(in: .whitespaces)
            }
        }
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.last?.trimmingCharacters(in: .whitespaces) ?? basePrompt
    }

    open func sessionPreparation() async throws {
        try await disablePaging()
        try await setBasePrompt()
    }

    /// Full signature — real default no-op-safe behavior removed;
    /// still throws by default (a device that hasn't overridden this
    /// genuinely hasn't decided how to disable paging), but every
    /// parameter shape needed across the vendor set is now present.
    @discardableResult
    open func disablePaging(
        command: String = "",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "disablePaging() is not implemented for \(profile.deviceType)"
        )
    }

    open func setTerminalWidth(
        command: String = "",
        pattern: String? = nil,
        cmdVerify: Bool = true
    ) async throws {
        guard !command.isEmpty else { return }
        let waitPattern = pattern ?? command
        try await writeChannel(command + profile.returnCharacter)
        _ = try await readUntilPattern(pattern: waitPattern)
    }

    // MARK: Enable mode

    @discardableResult
    open func enterEnableMode(
        secret: String,
        command: String = "enable",
        pattern: String = "ssword",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Enable mode is not implemented for \(profile.deviceType)"
        )
    }

    open func isInEnableMode(checkString: String = "#") async throws -> Bool {
        let prompt = try await findPrompt()
        return prompt.contains(checkString)
    }

    @discardableResult
    open func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Exiting enable mode is not implemented for \(profile.deviceType)"
        )
    }

    /// New hook: some drivers (Check Point Gaia) need enterEnableMode
    /// to delegate the actual secret-sending step to an overridable
    /// sub-method rather than always inlining it. Not yet wired into
    /// the default enterEnableMode() flow above — deferred, see notes
    /// at the bottom of this file.
    open func enableSecretHandler(
        pattern: String,
        output: String,
        caseInsensitive: Bool = true
    ) async throws -> String {
        output
    }

    // MARK: Config mode

    @discardableResult
    open func enterConfigMode(
        command: String = "",
        pattern: String = "",
        dotAll: Bool = false
    ) async throws -> String {
        guard supportsConfigMode else {
            throw SwiftmikoError.configModeNotSupported
        }
        inConfigMode = true
        return ""
    }

    @discardableResult
    open func exitConfigMode(
        exitConfig: String = "exit",
        pattern: String = ""
    ) async throws -> String {
        inConfigMode = false
        return ""
    }

    open func isInConfigMode(
        checkString: String = ")#",
        pattern: String = "[>#]"
    ) async throws -> Bool {
        inConfigMode
    }

    /// Regex-match variant, split out rather than a boolean
    /// `forceRegex:` flag (see the A10 translation for the reasoning).
    open func isInConfigModeRegex(
        checkString: String,
        pattern: String = ""
    ) async throws -> Bool {
        try await writeChannel(profile.returnCharacter)
        let output = try await readUntilPattern(pattern: pattern.isEmpty ? promptPattern : pattern)
        return output.range(of: checkString, options: .regularExpression) != nil
    }

    // MARK: Login (Telnet / Serial)

    /// Confirmed needed by many Telnet drivers. Base implementation
    /// is a straightforward username/password exchange; drivers with
    /// vendor-specific banners override it entirely.
    @discardableResult
    open func telnetLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(?:username|login)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        var output = ""
        for _ in 0..<maxLoops {
            let combined = "(?:\(usernamePattern)|\(passwordPattern)|\(primaryTerminator)|\(altTerminator))"
            let chunk = try await readUntilPattern(pattern: combined, caseInsensitive: true)
            output += chunk
            if chunk.range(of: usernamePattern, options: [.regularExpression, .caseInsensitive]) != nil {
                try await writeChannel(profile.username + telnetReturn)
            } else if chunk.range(of: passwordPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                if case .password(let password) = profile.auth {
                    try await writeChannel(password + telnetReturn)
                }
            } else {
                return output
            }
        }
        throw SwiftmikoError.authenticationFailed("Login failed: \(profile.host)")
    }

    /// Confirmed needed by Furukawa's Serial driver, which relies on
    /// this delegating straight to telnetLogin().
    @discardableResult
    open func serialLogin(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        usernamePattern: String = "(?:username|login)",
        passwordPattern: String = "assword",
        delay: TimeInterval = 1.0,
        maxLoops: Int = 20
    ) async throws -> String {
        try await telnetLogin(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            usernamePattern: usernamePattern,
            passwordPattern: passwordPattern,
            delay: delay,
            maxLoops: maxLoops
        )
    }

    /// Netmiko's TELNET_RETURN — Telnet conventionally uses "\r\n"
    /// regardless of the profile's configured returnCharacter.
    public nonisolated var telnetReturn: String { "\r\n" }

    // MARK: Cleanup (distinct from disconnect)

    /// Was absent — disconnect() played this role too, conflating
    /// "close the transport" with "run the device's own graceful
    /// logout sequence." Confirmed needed by ~15 drivers with custom
    /// logout banners/confirmations.
    open func cleanup(command: String = "exit") async throws {
        sessionLog?.fin = true
        try await writeChannel(command + profile.returnCharacter)
    }

    open func autodetectFileSystem(
        command: String = "dir",
        pattern: String = #"Directory of (.*)/"#
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Filesystem autodetection is not implemented for \(profile.deviceType)"
        )
    }

    // MARK: Delay scaling

    /// Confirmed needed by CDOT CROS, Check Point Gaia, and every
    /// driver whose Python source scaled a sleep by
    /// `self.global_delay_factor`. Prior translations hardcoded flat
    /// sleeps, silently dropping this.
    public nonisolated func selectDelayFactor(_ base: Double) -> Double {
        base * profile.globalDelayFactor
    }

    // MARK: Compatibility helpers

    public func normalizeCommand(_ command: String) -> String {
        command + profile.returnCharacter
    }

    public func clearBuffer() async throws {
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            let data = try await readChannel()
            if data.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    open func normalizeLinefeeds(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: profile.responseReturnCharacter)
            .replacingOccurrences(of: "\r", with: profile.responseReturnCharacter)
    }

    public var responseReturn: String { profile.responseReturnCharacter }

    public func setChannel(_ channel: any Channel) {
        self.channel = channel
    }

    /// Confirmed needed by CloudGenix and internally by SSHDetect —
    /// promoted from a private helper into a general method.
    open func stripBackspaces(_ input: String) -> String {
        var result = input
        while let range = result.range(of: #".\u{08}"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.replacingOccurrences(of: "\u{08}", with: "")
    }

    /// New — was a fixed pass-through; needed by Audiocode, Zyxel,
    /// Dell Isilon, IIJ SEIL OS, Huawei, and others.
    open func stripAnsiEscapeCodes(_ input: String) -> String {
        input.replacingOccurrences(
            of: #"\x1b\[[0-9;]*[a-zA-Z]"#,
            with: "",
            options: .regularExpression
        )
    }

    /// The internal hook sendCommand should consult for its
    /// expect-pattern, distinct from just always using basePrompt.
    /// Confirmed needed by HP Comware and ZPE Nodegrid.
    open func promptHandler(autoFindPrompt: Bool) async -> String {
        if autoFindPrompt, let found = try? await findPrompt() {
            return NSRegularExpression.escapedPattern(for: found)
        }
        return NSRegularExpression.escapedPattern(for: basePrompt)
    }

    // MARK: Output normalization

    private func normalizeOutput(_ output: String) -> String {
        var result = normalizeLinefeeds(output)
        if ansiEscapeCodes {
            result = stripAnsiEscapeCodes(result)
        }
        return result
    }

    /// Renamed from `stripCommandEcho` and promoted to `open` —
    /// confirmed needed by Audiocode, CloudGenix, MikroTik.
    open func stripCommand(_ commandString: String, output: String) -> String {
        var lines = output.components(separatedBy: .newlines)
        if lines.first?.contains(commandString) == true {
            lines.removeFirst()
        }
        return lines.joined(separator: responseReturn)
    }

    /// Renamed from `stripTrailingPrompt` and promoted to `open` —
    /// confirmed needed by NetScaler, Nodegrid, Audiocode, MikroTik,
    /// Juniper, FlexVNF, PAN-OS, Keymile, and others.
    open func stripPrompt(_ output: String) -> String {
        var lines = output.components(separatedBy: responseReturn)
        if let last = lines.last, !basePrompt.isEmpty, last.contains(basePrompt) {
            lines.removeLast()
        }
        return lines.joined(separator: responseReturn)
            .trimmingCharacters(in: .newlines)
    }
}
