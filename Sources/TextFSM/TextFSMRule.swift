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
//  TextFSMRule.swift
//  Swiftmiko
//
//  Port of textfsm.parser.TextFSMRule: parses a single state-machine
//  rule line of the form
//      ^regex -> [LineOp][.RecordOp] [NewState]
//  including `${ValueName}` substitution of previously-declared Values
//  into the regex before it's compiled.
//

import Foundation

enum TextFSMLineOp: String {
    case next = "Next"
    case `continue` = "Continue"
    case error = "Error"
}

enum TextFSMRecordOp: String {
    case noRecord = "NoRecord"
    case record = "Record"
    case clear = "Clear"
    case clearall = "Clearall"
}

final class TextFSMRule {
    let lineNumber: Int
    let regex: NSRegularExpression
    /// Synthetic (ICU-safe) group name -> original Value name. Needed
    /// because ${Name} substitution assembles several Values' templates
    /// into one pattern, and any of those names (or an ad-hoc named group
    /// written directly in the rule) may contain underscores ICU rejects.
    private let groupNameMapping: [String: String]
    let lineOp: TextFSMLineOp
    let recordOp: TextFSMRecordOp
    /// For every line op except `Error`, this is the next state name (or
    /// empty for "stay in the current state"). For `Error`, this holds the
    /// error message instead — mirrors upstream overloading the same slot.
    let newState: String

    init(line rawLine: String, lineNumber: Int, valueTemplates: [String: String]) throws {
        self.lineNumber = lineNumber
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else {
            throw TextFSMTemplateError.malformedRuleLine(line: rawLine, lineNumber: lineNumber)
        }

        let (matchText, actionText) = Self.splitMatchAction(line)
        let substituted = try Self.substituteValues(matchText, valueTemplates: valueTemplates, lineNumber: lineNumber)
        let icuPattern = TextFSMValue.translatePythonRegexSyntax(substituted)
        let (sanitized, mapping) = TextFSMRegexSupport.sanitizeNamedGroups(in: icuPattern)
        guard let compiled = try? NSRegularExpression(pattern: sanitized) else {
            throw TextFSMTemplateError.invalidRegex(regex: substituted, lineNumber: lineNumber)
        }
        self.regex = compiled
        self.groupNameMapping = mapping

        guard let actionText else {
            self.lineOp = .next
            self.recordOp = .noRecord
            self.newState = ""
            return
        }

        let (lineOp, recordOp, rawNewState) = try Self.parseAction(actionText, lineNumber: lineNumber)

        if lineOp == .continue, !rawNewState.isEmpty {
            throw TextFSMTemplateError.continueWithNewState(lineNumber: lineNumber)
        }
        // Validated against the RAW (still-quoted) text, matching upstream's
        // `re.match(r'\w+', self.new_state)` — a quoted state name like
        // `"Foo"` must be rejected for every line op except Error, since
        // `"` isn't a word character. Stripping quotes first (as an earlier
        // version of this file did) would let a quoted non-Error state name
        // slip through, since the UNQUOTED text alone can look alphanumeric.
        if lineOp != .error, !rawNewState.isEmpty,
           rawNewState.range(of: "^\\w+", options: .regularExpression) == nil {
            throw TextFSMTemplateError.invalidStateName(name: rawNewState, lineNumber: lineNumber)
        }

        self.lineOp = lineOp
        self.recordOp = recordOp
        self.newState = Self.stripQuotes(rawNewState)
    }

    /// Named-group captures from a successful match against this rule's
    /// regex, keyed by the ORIGINAL (possibly underscored) Value name —
    /// translates back through `groupNameMapping` so callers never see the
    /// synthetic ICU-safe names.
    func matchedValues(in match: NSTextCheckingResult, line: String) -> [(name: String, text: String)] {
        var results: [(name: String, text: String)] = []
        for (synthetic, originalName) in groupNameMapping {
            let r = match.range(withName: synthetic)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: line) else { continue }
            results.append((originalName, String(line[swiftRange])))
        }
        return results
    }

    // MARK: Splitting "regex -> action" (mirrors MATCH_ACTION)

    /// `(?<match>.*)(\s->(?<action>.*))` — greedy, so this finds the LAST
    /// `\s->` in the line, matching upstream's backtracking behavior.
    private static let matchActionRegex = try! NSRegularExpression(
        pattern: #"(?<match>.*)(\s->(?<action>.*))"#
    )

    private static func splitMatchAction(_ line: String) -> (match: String, action: String?) {
        let range = NSRange(line.startIndex..., in: line)
        guard let result = matchActionRegex.firstMatch(in: line, range: range) else {
            return (line, nil)
        }
        let matchRange = result.range(withName: "match")
        let actionRange = result.range(withName: "action")
        let matchText = Range(matchRange, in: line).map { String(line[$0]) } ?? line
        let actionText = Range(actionRange, in: line).map { String(line[$0]) }
        return (matchText, actionText)
    }

    // MARK: ${ValueName} substitution (mirrors string.Template.substitute)

    private static func substituteValues(
        _ text: String, valueTemplates: [String: String], lineNumber: Int
    ) throws -> String {
        var result = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            guard chars[i] == "$" else {
                result.append(chars[i])
                i += 1
                continue
            }
            if i + 1 < chars.count, chars[i + 1] == "$" {
                result.append("$")
                i += 2
                continue
            }
            if i + 1 < chars.count, chars[i + 1] == "{" {
                guard let closeOffset = chars[(i + 2)...].firstIndex(of: "}") else {
                    throw TextFSMTemplateError.variableSubstitutionFailed(text: text, lineNumber: lineNumber)
                }
                let name = String(chars[(i + 2)..<closeOffset])
                guard let replacement = valueTemplates[name] else {
                    throw TextFSMTemplateError.variableSubstitutionFailed(text: text, lineNumber: lineNumber)
                }
                result.append(replacement)
                i = closeOffset + 1
                continue
            }
            var j = i + 1
            while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
            guard j > i + 1 else {
                throw TextFSMTemplateError.variableSubstitutionFailed(text: text, lineNumber: lineNumber)
            }
            let name = String(chars[(i + 1)..<j])
            guard let replacement = valueTemplates[name] else {
                throw TextFSMTemplateError.variableSubstitutionFailed(text: text, lineNumber: lineNumber)
            }
            result.append(replacement)
            i = j
        }
        return result
    }

    // MARK: Action parsing (mirrors ACTION_RE / ACTION2_RE / ACTION3_RE)

    // Group names avoid underscores — ICU named capture groups only
    // accept [A-Za-z][A-Za-z0-9]*. These are purely internal (never
    // surfaced to callers), so a straight rename is enough; no mapping
    // needed, unlike the user-facing Value names elsewhere in this file.
    private static let actionRE = try! NSRegularExpression(
        pattern: #"^\s+(?<lnop>Continue|Next|Error)(\.(?<recop>Clear|Clearall|Record|NoRecord))?(\s+(?<newstate>\w+|".*"))?$"#
    )
    private static let action2RE = try! NSRegularExpression(
        pattern: #"^\s+(?<recop>Clear|Clearall|Record|NoRecord)(\s+(?<newstate>\w+|".*"))?$"#
    )
    private static let action3RE = try! NSRegularExpression(
        pattern: #"^(\s+(?<newstate>\w+|".*"))?$"#
    )

    private static func parseAction(
        _ action: String, lineNumber: Int
    ) throws -> (TextFSMLineOp, TextFSMRecordOp, String) {
        let range = NSRange(action.startIndex..., in: action)

        // Deliberately does NOT strip quotes here — the caller validates
        // "newstate" against the raw (possibly still-quoted) text first;
        // see the comment at the call site in init().
        func group(_ result: NSTextCheckingResult, _ name: String) -> String? {
            let r = result.range(withName: name)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: action) else { return nil }
            return String(action[swiftRange])
        }

        if let result = actionRE.firstMatch(in: action, range: range) {
            let lineOp = group(result, "lnop").flatMap(TextFSMLineOp.init(rawValue:)) ?? .next
            let recordOp = group(result, "recop").flatMap(TextFSMRecordOp.init(rawValue:)) ?? .noRecord
            return (lineOp, recordOp, group(result, "newstate") ?? "")
        }
        if let result = action2RE.firstMatch(in: action, range: range) {
            let recordOp = group(result, "recop").flatMap(TextFSMRecordOp.init(rawValue:)) ?? .noRecord
            return (.next, recordOp, group(result, "newstate") ?? "")
        }
        if let result = action3RE.firstMatch(in: action, range: range) {
            return (.next, .noRecord, group(result, "newstate") ?? "")
        }
        throw TextFSMTemplateError.malformedRuleLine(line: action, lineNumber: lineNumber)
    }

    private static func stripQuotes(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }
}
