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
// Sources/Swiftmiko/Netscaler/Netscaler.swift

import Foundation

/// Citrix NetScaler SSH driver.
///
/// Maps to netmiko's NetscalerSSH(NoConfig, BaseConnection).
///
/// No configuration mode via this connection — NetScaler's config is
/// managed through its own "set"/"add"/"show" command vocabulary
/// directly at the normal prompt, not a distinct config mode — hence
/// NoConfig.
public final class NetscalerSSH: BaseConnection, NoConfig {

    // MARK: Session Preparation

    /// Maps to netmiko's:
    ///     self._test_channel_read(pattern=r"[>#]")
    ///     self.set_base_prompt()
    ///     cmd = f"{self.RETURN}set cli mode -page OFF{self.RETURN}"
    ///     self.disable_paging(command=cmd)
    ///     self.set_base_prompt()
    ///
    /// Note the paging-disable command is wrapped in return characters
    /// on both sides, not just terminated by one at the end the way
    /// most disablePaging commands are — NetScaler apparently needs a
    /// leading return to ensure the command starts on a clean line.
    /// setBasePrompt() is deliberately called a second time after
    /// disabling paging, since the "set cli mode" command's own
    /// confirmation output can otherwise leave stale prompt text
    /// behind that the first detection captured.
    override public func sessionPreparation() async throws {
        try await testChannelRead(pattern: "[>#]")
        try await setBasePrompt()

        let pagingCommand = profile.returnCharacter +
            "set cli mode -page OFF" +
            profile.returnCharacter
        try await disablePaging(command: pagingCommand)

        try await setBasePrompt()
    }

    // MARK: Prompt Detection

    /// Sets basePrompt. NetScaler only ever presents '>' as its
    /// prompt terminator in practice, but both terminator parameters
    /// are accepted for interface parity with the base signature.
    ///
    /// Maps to netmiko's set_base_prompt(pri_prompt_terminator=">",
    /// alt_prompt_terminator="#").
    ///
    /// If the base implementation's detection comes back empty (an
    /// edge case where nothing matched cleanly), this falls back to
    /// just using the bare primary terminator string as the prompt
    /// rather than leaving basePrompt empty or throwing.
    override public func setBasePrompt(
        primaryTerminator: String = ">",
        altTerminator: String = "#",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        if basePrompt.isEmpty {
            basePrompt = primaryTerminator
        }
    }

    // MARK: Output Stripping

    /// Strip a trailing "Done" line from command output, on top of
    /// the base class's normal prompt stripping.
    ///
    /// Maps to netmiko's strip_prompt().
    ///
    /// NetScaler appends a literal "Done" line after successful
    /// commands, similar in spirit to how some devices append a
    /// confirmation banner — this removes it so command output stays
    /// clean for the caller.
    override public func stripPrompt(_ output: String) -> String {
        let cleaned = super.stripPrompt(output)
        var lines = cleaned.components(separatedBy: responseReturn)
        guard let last = lines.last, last.contains("Done") else {
            return cleaned
        }
        lines.removeLast()
        return lines.joined(separator: responseReturn)
    }
}
