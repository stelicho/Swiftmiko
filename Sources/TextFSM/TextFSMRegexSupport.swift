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
//  TextFSMRegexSupport.swift
//  Swiftmiko
//
//  ICU (NSRegularExpression's engine) only accepts [A-Za-z][A-Za-z0-9]*
//  for named capture groups — no underscores. Python's `re`, which real
//  TextFSM value names are written against, allows underscores and they
//  are routinely used in practice (VLAN_ID, INTERFACE_NAME, and similar
//  appear throughout ntc-templates). Compiling a pattern built from
//  `(?<VLAN_ID>...)` fails outright rather than just behaving oddly, so
//  every named group textfsm would create gets rewritten here to an
//  ICU-safe synthetic name before compilation, with the original name
//  recoverable afterward via the returned mapping.
//

import Foundation

enum TextFSMRegexSupport {
    /// Rewrites every `(?<name>` in `pattern` to an ICU-safe synthetic
    /// name (`g0`, `g1`, ...), returning the rewritten pattern plus a
    /// synthetic -> original name mapping. Skips lookbehind assertions
    /// (`(?<=`, `(?<!`), which use the same two leading characters but
    /// aren't named groups at all.
    static func sanitizeNamedGroups(in pattern: String) -> (pattern: String, mapping: [String: String]) {
        var result = ""
        var mapping: [String: String] = [:]
        var counter = 0
        let chars = Array(pattern)
        var i = 0

        while i < chars.count {
            if chars[i] == "(", i + 2 < chars.count, chars[i + 1] == "?", chars[i + 2] == "<",
               i + 3 < chars.count, chars[i + 3] != "=", chars[i + 3] != "!",
               let closeOffset = chars[(i + 3)...].firstIndex(of: ">") {
                let originalName = String(chars[(i + 3)..<closeOffset])
                let synthetic = "g\(counter)"
                counter += 1
                mapping[synthetic] = originalName
                result += "(?<\(synthetic)>"
                i = closeOffset + 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return (result, mapping)
    }
}
