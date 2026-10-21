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
// Sources/Swiftmiko/Ciena/CienaSaos.swift

import Foundation

/// Common implementation for Ciena SAOS devices.
///
/// Maps to netmiko's CienaSaosBase(NoEnable, NoConfig, BaseConnection).
///
/// No privilege escalation and no configuration mode via this
/// connection type — hence NoEnable + NoConfig. Ciena's prompt
/// terminator varies by device: it can end in '>', '$', or '#'
/// depending on model and firmware, which is why prompt detection
/// here is more involved than most drivers.
open class CienaSaosBase: BaseConnection, NoEnable, NoConfig {

    // NoConfig: real Netmiko's mixin is a trivial pass-through
    // (check_config_mode->True, config_mode/exit_config_mode->""),
    // not a throw — see Sources/NoConfig.swift for why this needs a
    // direct override rather than a protocol extension default.
    override public func isInConfigMode(checkString: String = "", pattern: String = "") async throws -> Bool {
        NoConfigBehavior.isInConfigMode()
    }

    @discardableResult
    override public func enterConfigMode(command: String = "", pattern: String = "", dotAll: Bool = false) async throws -> String {
        NoConfigBehavior.enter()
    }

    @discardableResult
    override public func exitConfigMode(exitConfig: String = "exit", pattern: String = "") async throws -> String {
        NoConfigBehavior.exit()
    }

    // NoEnable: same trivial-pass-through story — see Sources/NoEnable.swift.
    override public func isInEnableMode(checkString: String = "") async throws -> Bool {
        NoEnableBehavior.isInEnableMode()
    }

    @discardableResult
    override public func enterEnableMode(
        secret: String,
        command: String = "",
        pattern: String = "",
        enablePattern: String? = nil,
        checkState: Bool = true,
        caseInsensitive: Bool = true,
        defaultUsername: String = ""
    ) async throws -> String {
        NoEnableBehavior.enter()
    }

    @discardableResult
    override public func exitEnableMode(exitCommand: String = "exit") async throws -> String {
        NoEnableBehavior.exit()
    }

    override public nonisolated var promptPattern: String { "[>#$]" }

    // MARK: Prompt Detection

    /// Detect the base prompt, accepting any of Ciena's three
    /// possible terminator characters.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="",
    /// alt_prompt_terminator="").
    ///
    /// Note both terminator parameters default to empty strings here
    /// — unlike every other driver in this vendor set, this method
    /// doesn't build its search pattern from the terminator
    /// parameters at all. It always searches using promptPattern
    /// directly, then validates the result with a second regex
    /// (anything, followed by one of >, #, or $, anchored to end of
    /// line) before strips off exactly the last character as the
    /// terminator.
    override public func setBasePrompt(
        primaryTerminator: String = "",
        altTerminator: String = "",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        let prompt = try await findPrompt(delay: delay)

        let validationPattern = "^.+\(promptPattern)$"
        guard prompt.range(of: validationPattern, options: .regularExpression) != nil else {
            throw SwiftmikoError.unexpectedPrompt(
                "Router prompt not found: \(prompt.debugDescription)"
            )
        }

        basePrompt = String(prompt.dropLast(1))
    }

    /// CienaSaosBase extends BaseConnection directly, whose
    /// disablePaging() unconditionally throws — this gives it the same
    /// real generic behavior CiscoBaseConnection-rooted drivers get.
    /// sessionPreparation() always passes its own explicit command, so
    /// this override's own default is never actually relied upon.
    @discardableResult
    override public func disablePaging(
        command: String = "system shell session set more off",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await genericDisablePaging(command: command)
    }

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=self.prompt_pattern)
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="system shell session set more off")
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: promptPattern)
        try await setBasePrompt()
        try await disablePaging(command: "system shell session set more off")
    }

    // MARK: Shell Access

    /// Enter the underlying Bourne shell.
    ///
    /// Maps to netmiko's _enter_shell().
    ///
    /// Unlike every prior "_enter_shell" we've translated, this one
    /// actively checks for a specific failure string in the output —
    /// "SHELL PARSER FAILURE" — and throws a clear, actionable error
    /// explaining that SCP support on this platform requires
    /// "diag shell" permissions the connecting account may not have.
    /// This matters because SCP file transfers on this platform depend
    /// on this method succeeding (see enterShellForFileTransfer()
    /// below); a permissions problem here would otherwise surface as a
    /// confusing downstream failure instead of a clear one at the
    /// point of actual cause.
    ///
    /// Note: no CienaSaosFileTransfer class exists yet in this vendor
    /// set, so nothing currently calls this through SCPHandler — this
    /// override exists in advance so SCP support only needs a
    /// FileTransfer subclass, not a change here, whenever it's added.
    @discardableResult
    internal func enterShell() async throws -> String {
        let output = try await sendCommand(
            "diag shell",
            expectString: promptPattern
        )
        guard !output.contains("SHELL PARSER FAILURE") else {
            throw SwiftmikoError.authenticationFailed(
                "SCP support on Ciena SAOS requires 'diag shell' permissions"
            )
        }
        return output
    }

    /// Return to the Ciena SAOS CLI from the Bourne shell.
    /// Maps to netmiko's _return_cli().
    @discardableResult
    internal func returnCLI() async throws -> String {
        return try await sendCommand("exit", expectString: ">")
    }

    override public func enterShellForFileTransfer() async throws {
        _ = try await enterShell()
    }

    override public func returnFromShellForFileTransfer() async throws {
        _ = try await returnCLI()
    }

    // MARK: Save Config

    /// Maps to netmiko's save_config(cmd="configuration save").
    public func saveConfig(
        command: String = "configuration save",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        return try await sendCommand(
            command,
            readTimeout: 100.0,
            stripPrompt: false,
            stripCommand: false
        )
    }
}

// MARK: - CienaSaosSSH

/// Ciena SAOS SSH driver — no differences from the base.
/// Maps to netmiko's CienaSaosSSH(CienaSaosBase).
public final class CienaSaosSSH: CienaSaosBase {}

// MARK: - CienaSaos10SSH

/// Ciena SAOS 10 SSH driver.
///
/// Maps to netmiko's CienaSaos10SSH(NoEnable, BaseConnection).
///
/// IMPORTANT: this does NOT subclass CienaSaosBase, despite the
/// similar name and overlapping purpose. It's an entirely separate
/// class in Netmiko's own source, inheriting directly from
/// BaseConnection. That means it does NOT get NoConfig conformance,
/// the custom multi-terminator setBasePrompt() above, the shell
/// helper methods, or the custom saveConfig() override — it relies
/// entirely on BaseConnection's own defaults for all of those.
///
/// This is preserved exactly as structured in the Python source
/// rather than "corrected" into a CienaSaosBase subclass, since doing
/// so would be a behavioral change beyond what was actually asked
/// for — SAOS 10 may genuinely differ enough from SAOS 6/8 elsewhere
/// that this separation is deliberate, even though this single file
/// doesn't show enough evidence either way. Worth confirming against
/// a real SAOS 10 device, or a newer Netmiko release, before assuming
/// this is intentional versus an oversight in the original.
public final class CienaSaos10SSH: BaseConnection, NoEnable {

    /// CienaSaos10SSH extends BaseConnection directly, whose
    /// disablePaging() unconditionally throws — this gives it the same
    /// real generic behavior CiscoBaseConnection-rooted drivers get.
    /// sessionPreparation() always passes its own explicit command, so
    /// this override's own default is never actually relied upon.
    @discardableResult
    override public func disablePaging(
        command: String = "set session more off",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        try await genericDisablePaging(command: command)
    }

    /// Maps to netmiko's session_preparation():
    ///     self._test_channel_read()
    ///     self.set_base_prompt()
    ///     self.disable_paging(command="set session more off")
    ///
    /// Note testChannelRead() is called with NO pattern argument at
    /// all here — unlike the sibling CienaSaosBase.sessionPreparation(),
    /// which passes promptPattern explicitly. Also note the paging
    /// command differs: "set session more off" here versus
    /// "system shell session set more off" in the main driver — a
    /// real, confirmed difference between SAOS 10 and earlier SAOS
    /// versions' CLI vocabulary, not a translation inconsistency.
    override public func sessionPreparation() async throws {
        try await testChannelRead()
        try await setBasePrompt()
        try await disablePaging(command: "set session more off")
    }
}

// MARK: - CienaSaosTelnet

/// Ciena SAOS Telnet driver.
/// Maps to netmiko's CienaSaosTelnet(CienaSaosBase). Overrides the
/// default line ending to "\r\n" unless the caller's profile already
/// specifies one.
public final class CienaSaosTelnet: CienaSaosBase {

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
}
