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
//  CiscoASA.swift
//  Swiftmiko
//
import Foundation

public class CiscoASASSH: CiscoSSHConnection {

    override public func setBasePrompt(
        primaryTerminator: String = "#",
        altTerminator: String = ">",
        delay: TimeInterval = 1.0,
        pattern: String? = nil
    ) async throws {
        // Let the parent detect the prompt normally
        try await super.setBasePrompt(
            primaryTerminator: primaryTerminator,
            altTerminator: altTerminator,
            delay: delay,
            pattern: pattern
        )
        // ASA multi-context: strip trailing (conf... from prompt
        // e.g. "fw1(config)" → "fw1"
        let detected = basePrompt
        if let match = detected.range(of: #"^(.*)\(conf"#, options: .regularExpression) {
            if let regex = try? NSRegularExpression(pattern: #"^(.*)\(conf"#),
               let m = regex.firstMatch(in: detected, range: NSRange(detected.startIndex..., in: detected)),
               m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: detected) {
                basePrompt = String(detected[r])
            }
            _ = match
        }
    }

    @discardableResult
    override public func sendCommand(
        _ command: String,
        readTimeout: TimeInterval? = nil,
        expectString: String? = nil,
        stripPrompt: Bool = true,
        stripCommand: Bool = true,
        cmdVerify: Bool = true,
        autoFindPrompt: Bool = true
    ) async throws -> String {
        let output = try await super.sendCommand(
            command,
            readTimeout: readTimeout,
            expectString: expectString,
            stripPrompt: stripPrompt,
            stripCommand: stripCommand,
            cmdVerify: cmdVerify,
            autoFindPrompt: autoFindPrompt
        )
        // Multi-context: re-detect prompt after every context switch
        if command.contains("changeto") {
            try await setBasePrompt()
        }
        return output
    }

    // ASA has unusual \r\n\r sequences
    override public func normalizeLinefeeds(_ input: String) -> String {
        var result = input
        for pattern in ["\r\n\r", "\r\r\r\n", "\r\r\n", "\r\n", "\n\r"] {
            result = result.replacingOccurrences(of: pattern, with: responseReturn)
        }
        if responseReturn == "\n" {
            result = result.replacingOccurrences(of: "\r", with: "")
        }
        return result
    }
}
