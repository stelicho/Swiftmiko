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
    let namedGroupNames: [String]
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
        guard let compiled = try? NSRegularExpression(pattern: icuPattern) else {
            throw TextFSMTemplateError.invalidRegex(regex: substituted, lineNumber: lineNumber)
        }
        self.regex = compiled
        self.namedGroupNames = compiled.swiftmikoNamedGroupNames()

        guard let actionText else {
            self.lineOp = .next
            self.recordOp = .noRecord
            self.newState = ""
            return
        }

        let (lineOp, recordOp, newState) = try Self.parseAction(actionText, lineNumber: lineNumber)

        if lineOp == .continue, !newState.isEmpty {
            throw TextFSMTemplateError.continueWithNewState(lineNumber: lineNumber)
        }
        if lineOp != .error, !newState.isEmpty,
           newState.range(of: "^\\w+", options: .regularExpression) == nil {
            throw TextFSMTemplateError.invalidStateName(name: newState, lineNumber: lineNumber)
        }

        self.lineOp = lineOp
        self.recordOp = recordOp
        self.newState = newState
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

    private static let actionRE = try! NSRegularExpression(
        pattern: #"^\s+(?<ln_op>Continue|Next|Error)(\.(?<rec_op>Clear|Clearall|Record|NoRecord))?(\s+(?<new_state>\w+|".*"))?$"#
    )
    private static let action2RE = try! NSRegularExpression(
        pattern: #"^\s+(?<rec_op>Clear|Clearall|Record|NoRecord)(\s+(?<new_state>\w+|".*"))?$"#
    )
    private static let action3RE = try! NSRegularExpression(
        pattern: #"^(\s+(?<new_state>\w+|".*"))?$"#
    )

    private static func parseAction(
        _ action: String, lineNumber: Int
    ) throws -> (TextFSMLineOp, TextFSMRecordOp, String) {
        let range = NSRange(action.startIndex..., in: action)

        func group(_ result: NSTextCheckingResult, _ name: String) -> String? {
            let r = result.range(withName: name)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: action) else { return nil }
            return stripQuotes(String(action[swiftRange]))
        }

        if let result = actionRE.firstMatch(in: action, range: range) {
            let lineOp = group(result, "ln_op").flatMap(TextFSMLineOp.init(rawValue:)) ?? .next
            let recordOp = group(result, "rec_op").flatMap(TextFSMRecordOp.init(rawValue:)) ?? .noRecord
            return (lineOp, recordOp, group(result, "new_state") ?? "")
        }
        if let result = action2RE.firstMatch(in: action, range: range) {
            let recordOp = group(result, "rec_op").flatMap(TextFSMRecordOp.init(rawValue:)) ?? .noRecord
            return (.next, recordOp, group(result, "new_state") ?? "")
        }
        if let result = action3RE.firstMatch(in: action, range: range) {
            return (.next, .noRecord, group(result, "new_state") ?? "")
        }
        throw TextFSMTemplateError.malformedRuleLine(line: action, lineNumber: lineNumber)
    }

    private static func stripQuotes(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        return String(text.dropFirst().dropLast())
    }
}
