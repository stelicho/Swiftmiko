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
// Sources/Swiftmiko/Fortinet/Fortinet.swift

import Foundation

/// Fortinet FortiOS SSH driver.
///
/// Maps to netmiko's FortinetSSH(NoConfig, NoEnable, CiscoSSHConnection).
///
/// No configuration mode and no privilege escalation via this
/// connection type — hence NoConfig + NoEnable. This is the most
/// stateful driver in the whole vendor set: disabling paging is not a
/// single fire-and-forget command, but a full navigate-in/change/
/// navigate-out sequence that depends on whether virtual domains
/// (VDOMs) are enabled and which major FortiOS version is running —
/// and the original setting is carefully restored on cleanup rather
/// than left changed.
public final class FortinetSSH: CiscoSSHConnection, NoConfig, NoEnable {

    override public nonisolated var promptPattern: String { "[#$]" }

    /// SSH key-exchange algorithms Fortinet devices are known to
    /// support reliably.
    /// Maps to netmiko's preferred_kex class-level set.
    private static let preferredKex: Set<String> = [
        "diffie-hellman-group14-sha1",
        "diffie-hellman-group-exchange-sha1",
        "diffie-hellman-group-exchange-sha256",
        "diffie-hellman-group1-sha1",
    ]

    // MARK: State

    /// Whether virtual domains are enabled on this device.
    /// Maps to netmiko's self._vdoms.
    private var vdomsEnabled: Bool = false

    /// The detected major FortiOS version family.
    /// Maps to netmiko's self._os_version.
    private enum FortiOSVersion { case v7OrLater, v6OrEarlier }
    private var osVersion: FortiOSVersion = .v7OrLater

    /// The output mode as it was originally configured on the
    /// device, before Swiftmiko changed anything — restored during
    /// cleanup.
    /// Maps to netmiko's self._original_output_mode.
    private var originalOutputMode: String = ""

    /// The output mode as Swiftmiko currently believes it to be.
    /// Maps to netmiko's self._output_mode.
    private var currentOutputMode: String = ""

    // MARK: Init

    /// Restrict the SSH key-exchange algorithm set to ones known to
    /// work reliably with FortiOS, unless the caller has already
    /// supplied their own KEX restrictions.
    ///
    /// Maps to netmiko's __init__ override:
    ///     disabled_algorithms = kwargs.get("disabled_algorithms")
    ///     if disabled_algorithms is None or not disabled_algorithms.get("kex"):
    ///         paramiko_transport = getattr(paramiko, "Transport")
    ///         paramiko_cur_kex = set(paramiko_transport._preferred_kex)
    ///         disabled_kex = list(paramiko_cur_kex - self.preferred_kex)
    ///         kwargs["disabled_algorithms"] = {"kex": disabled_kex}
    ///
    /// This is genuinely difficult to translate faithfully: Python
    /// reaches directly into Paramiko's Transport class attribute
    /// (`_preferred_kex`, a private implementation detail even in
    /// Paramiko's own naming convention) to compute which algorithms
    /// to disable — the full universe of default KEX algorithms MINUS
    /// the Fortinet-preferred subset. SwiftNIO SSH does not expose an
    /// equivalent private class-level default list the same way, and
    /// even if it did, reaching into another library's private
    /// implementation detail is fragile by design (Paramiko itself
    /// only exposes this via a leading-underscore attribute, meaning
    /// even the Python original is relying on non-public API).
    ///
    /// The safer, more maintainable translation is to express this as
    /// an ALLOW-list rather than a computed DENY-list: explicitly
    /// request only the Fortinet-preferred algorithms be offered
    /// during key exchange, rather than trying to reconstruct
    /// "everything SwiftNIO SSH would otherwise offer, minus these."
    /// This achieves the same practical outcome (only preferredKex
    /// algorithms get used) without depending on SwiftNIO SSH's
    /// internal defaults being enumerable or stable across versions.
    public init(
        profile: ConnectionProfile,
        sessionLog: SessionLogConfig? = nil,
        loggerEnabled: Bool = true,
        channel: (any Channel)? = nil,
        channelProvider: ChannelProvider? = nil
    ) {
        var adjustedProfile = profile
        if adjustedProfile.allowedKeyExchangeAlgorithms == nil {
            adjustedProfile.allowedKeyExchangeAlgorithms = Self.preferredKex
        }
        super.init(
            profile: adjustedProfile,
            sessionLog: sessionLog,
            loggerEnabled: loggerEnabled,
            channel: channel,
            channelProvider: channelProvider
        )
    }

    // MARK: Session Preparation

    /// Handle FortiOS's optional post-login banner acceptance, detect
    /// VDOM/version state, and record the device's current output
    /// mode before changing anything.
    ///
    /// Maps to netmiko's session_preparation().
    ///
    /// If "set post-login-banner enable" is configured, FortiOS
    /// requires pressing 'a' to accept the banner before login
    /// proceeds. This is detected and answered before prompt
    /// detection continues.
    override public func sessionPreparation() async throws {
        let data = try await testChannelRead(pattern: "to accept|\(promptPattern)")

        if data.contains("to accept") {
            try await writeChannel("a\r")
            _ = try await testChannelRead(pattern: promptPattern)
        }

        try await setBasePrompt()
        vdomsEnabled = try await checkVdomsEnabled()
        osVersion = try await determineOSVersion()

        // Retain how the output mode was ORIGINALLY configured, so
        // cleanup can restore it exactly — Swiftmiko should be a
        // considerate guest on this device, not leave a permanent
        // side effect behind just because a session happened to
        // connect.
        originalOutputMode = try await getOutputMode()
        currentOutputMode = originalOutputMode

        try await disablePaging()
    }

    // MARK: Prompt Detection

    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator="#",
    /// alt_prompt_terminator="$").
    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = "$",
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

    /// Maps to netmiko's find_prompt().
    override public func findPrompt(
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws -> String {
        return try await super.findPrompt(delay: delay, pattern: pattern ?? promptPattern)
    }

    // MARK: VDOM / Version Detection

    /// Determine whether virtual domains are enabled.
    /// Maps to netmiko's _vdoms_enabled().
    private func checkVdomsEnabled() async throws -> Bool {
        let output = try await sendCommand(
            "get system status | grep Virtual",
            expectString: promptPattern
        )
        return output.range(
            of: "Virtual domain configuration: (multiple|enable|split-task)",
            options: .regularExpression
        ) != nil
    }

    /// Enter 'config global' mode, needed on VDOM-enabled devices
    /// before most console-level settings can be changed.
    /// Maps to netmiko's _config_global().
    @discardableResult
    private func configGlobal() async throws -> String {
        do {
            return try await sendCommand("config global", expectString: promptPattern)
        } catch {
            throw SwiftmikoError.commandFailed(
                """

                Netmiko may require 'config global' access to properly disable output paging.
                Alternatively you can try configuring 'configure system console -> set output standard'.

                """
            )
        }
    }

    /// Exit 'config global' mode.
    /// Maps to netmiko's _exit_config_global().
    @discardableResult
    private func exitConfigGlobal() async throws -> String {
        do {
            return try await sendCommand("end", expectString: promptPattern)
        } catch {
            throw SwiftmikoError.commandFailed(
                "Unable to properly exit 'config global' mode."
            )
        }
    }

    /// Determine the running major FortiOS version family.
    /// Maps to netmiko's _determine_os_version().
    private func determineOSVersion() async throws -> FortiOSVersion {
        let output = try await sendCommand(
            "get system status | grep Version",
            expectString: promptPattern
        )
        if output.range(
            of: #"^Version: .* (v[78]\.).*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return .v7OrLater
        } else if output.range(
            of: #"^Version: .* (v[654]\.).*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return .v6OrEarlier
        } else {
            throw SwiftmikoError.commandFailed("Unexpected FortiOS Version encountered.")
        }
    }

    // MARK: Output Mode Detection

    /// Retrieve the current output mode, dispatching to the correct
    /// version-specific method — v6 and earlier don't support the v7
    /// command at all.
    /// Maps to netmiko's _get_output_mode().
    private func getOutputMode() async throws -> String {
        switch osVersion {
        case .v6OrEarlier:
            return try await getOutputModeV6()
        case .v7OrLater:
            return try await getOutputModeV7()
        }
    }

    /// FortiOS v6 and earlier: retrieve the output mode from a full
    /// configuration dump.
    /// Maps to netmiko's _get_output_mode_v6().
    private func getOutputModeV6() async throws -> String {
        if vdomsEnabled {
            _ = try await configGlobal()
        }

        let output = try await sendCommand("show full-configuration system console")

        if vdomsEnabled {
            _ = try await exitConfigGlobal()
        }

        return try Self.extractOutputMode(
            from: output,
            pattern: #"^\s+set output (\S+)\s*$"#
        )
    }

    /// FortiOS v7 and later: retrieve the output mode from a direct
    /// status command.
    /// Maps to netmiko's _get_output_mode_v7().
    private func getOutputModeV7() async throws -> String {
        if vdomsEnabled {
            _ = try await configGlobal()
        }

        let output = try await sendCommand(
            "get system console",
            expectString: promptPattern
        )

        if vdomsEnabled {
            _ = try await exitConfigGlobal()
        }

        return try Self.extractOutputMode(
            from: output,
            pattern: #"output\s+:\s+(\S+)\s*$"#
        )
    }

    /// Extract and validate a captured "mode" value from a
    /// version-specific output-mode command's response.
    ///
    /// Maps to the shared validation logic duplicated across
    /// _get_output_mode_v6() and _get_output_mode_v7() in Python —
    /// consolidated into one helper here since the pattern (capture a
    /// group, trim it, validate it's "more" or "standard") is
    /// identical between the two, just with a different regex.
    private static func extractOutputMode(
        from output: String,
        pattern: String
    ) throws -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            throw SwiftmikoError.commandFailed(
                "Unable to determine the output mode on the Fortinet device."
            )
        }
        let nsOutput = output as NSString
        guard let match = regex.firstMatch(
            in: output, range: NSRange(location: 0, length: nsOutput.length)
        ), match.numberOfRanges > 1 else {
            throw SwiftmikoError.commandFailed(
                "Unable to determine the output mode on the Fortinet device."
            )
        }

        let mode = nsOutput.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespaces)

        guard mode == "more" || mode == "standard" else {
            throw SwiftmikoError.commandFailed(
                "Unable to determine the output mode on the Fortinet device."
            )
        }
        return mode
    }

    // MARK: Paging

    /// Disable paging — a stateful, potentially multi-step operation
    /// rather than a single command.
    ///
    /// Maps to netmiko's disable_paging(command="terminal length 0").
    ///
    /// If the output mode is already "standard" (no paging), this
    /// does nothing at all — a genuine short-circuit, not just an
    /// optimization, since re-running the config sequence
    /// unnecessarily could have side effects on a live device.
    /// Otherwise, navigates into config global on VDOM-enabled
    /// devices, runs the three-command sequence to set output mode to
    /// "standard", tracks the new state, and navigates back out.
    ///
    /// Note the `command` parameter is accepted for interface parity
    /// with the base signature but genuinely unused — this override
    /// doesn't send an arbitrary command string at all, unlike every
    /// other disablePaging override in this vendor set.
    @discardableResult
    override public func disablePaging(
        command: String = "terminal length 0",
        delay: TimeInterval = 0.5,
        cmdVerify: Bool = true,
        pattern: String? = nil
    ) async throws -> String {
        guard currentOutputMode != "standard" else {
            return ""
        }

        var output = ""
        if vdomsEnabled {
            output += try await configGlobal()
        }

        let disablePagingCommands = [
            "config system console",
            "set output standard",
            "end",
        ]
        output += try await sendMultiline(disablePagingCommands, expectString: promptPattern)
        currentOutputMode = "standard"

        if vdomsEnabled {
            output += try await exitConfigGlobal()
        }
        return output
    }

    // MARK: Cleanup

    /// Re-enable paging globally if it was originally enabled,
    /// restoring the device to the state it was found in, before
    /// running the standard cleanup sequence.
    ///
    /// Maps to netmiko's cleanup(command="exit").
    ///
    /// This is the one driver in the whole vendor set that undoes a
    /// configuration change it made purely for automation's
    /// convenience — every other paging-disable in this codebase is
    /// left in place after disconnect. Fortinet's own device state
    /// (output mode) is treated as something Swiftmiko borrowed and
    /// must give back, not something it's entitled to leave changed.
    override public func cleanup(command: String = "exit") async throws {
        if originalOutputMode == "more" {
            if vdomsEnabled {
                _ = try await configGlobal()
            }
            let commands = ["config system console", "set output more", "end"]
            _ = try await sendMultiline(commands, expectString: promptPattern)
            if vdomsEnabled {
                _ = try await exitConfigGlobal()
            }
        }
        try await super.cleanup(command: command)
    }

    // MARK: Save Config

    /// Not supported on this platform.
    /// Maps to netmiko's save_config() raising NotImplementedError.
    override public func saveConfig(
        command: String = "",
        confirm: Bool = false,
        confirmResponse: String = ""
    ) async throws -> String {
        throw SwiftmikoError.notImplemented(
            "Fortinet does not support saveConfig()"
        )
    }
}
