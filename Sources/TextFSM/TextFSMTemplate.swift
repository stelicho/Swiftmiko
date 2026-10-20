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
//  TextFSMTemplate.swift
//  Swiftmiko
//
//  Port of textfsm.parser.TextFSM's template-parsing half: the Value
//  section at the top of a .textfsm file, followed by one or more named
//  State sections, each a bare state-name line followed by indented rule
//  lines. See TextFSMExecution.swift for the interpreter that actually
//  runs a parsed template against real input text.
//
//  Compatible with real ntc-templates (github.com/networktocode/ntc-templates)
//  files unmodified — this is not a simplified or Swiftmiko-specific
//  dialect of TextFSM.
//

import Foundation

public final class TextFSMTemplate {
    let values: [TextFSMValue]
    let states: [String: [TextFSMRule]]

    /// The declared Value names, in declaration order — matches
    /// textfsm's `.header` property.
    public var header: [String] { values.map(\.name) }

    public init(templateString: String) throws {
        var lines = templateString.components(separatedBy: "\n")
        lines = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

        var index = 0
        var lineNumber = 0
        var parsedValues: [TextFSMValue] = []

        // MARK: Value section — terminated by the first blank line.
        while index < lines.count {
            lineNumber += 1
            let line = lines[index]
            index += 1
            if line.isEmpty { break }
            if Self.isComment(line) { continue }
            guard line.hasPrefix("Value ") else {
                throw TextFSMTemplateError.malformedValueLine(line: line, lineNumber: lineNumber)
            }
            let value = try TextFSMValue(line: line, lineNumber: lineNumber)
            // Mirrors textfsm's `if value.name in self.header: raise ...` —
            // a duplicate Value name isn't just redundant: valueTemplates
            // below would silently overwrite the ${Name} substitution for
            // the first declaration, and matchedValues() only ever finds
            // the FIRST same-named TextFSMValue object by name, so the
            // second declaration's own assign()/clearVar() would never run.
            guard !parsedValues.contains(where: { $0.name == value.name }) else {
                throw TextFSMTemplateError.duplicateValueName(name: value.name, lineNumber: lineNumber)
            }
            parsedValues.append(value)
        }

        var valueTemplates: [String: String] = [:]
        for value in parsedValues { valueTemplates[value.name] = value.template }

        // MARK: State sections
        var states: [String: [TextFSMRule]] = [:]
        var currentState: String?

        while index < lines.count {
            lineNumber += 1
            let line = lines[index]
            index += 1

            if line.isEmpty {
                currentState = nil
                continue
            }
            if Self.isComment(line) { continue }

            if Self.looksLikeRuleLine(line) {
                guard let stateName = currentState else {
                    throw TextFSMTemplateError.malformedRuleLine(line: line, lineNumber: lineNumber)
                }
                let rule = try TextFSMRule(line: line, lineNumber: lineNumber, valueTemplates: valueTemplates)
                states[stateName, default: []].append(rule)
            } else if line.first == " " || line.first == "\t" {
                // Indented but not a valid '^'-prefixed rule — upstream's
                // exact "missing whitespace or caret" error applies here.
                throw TextFSMTemplateError.missingRuleIndentation(line: line, lineNumber: lineNumber)
            } else {
                // Mirrors textfsm's state_name_re match plus its length and
                // reserved-word checks — a state can't be named the same as
                // a line/record operator (e.g. a state literally named
                // "Record" or "Next"), and is capped at the same 48-char
                // limit as Value names.
                // Mirrors textfsm's state_name_re match plus its length and
                // reserved-word checks — a state can't be named the same as
                // a line/record operator (e.g. a state literally named
                // "Record" or "Next"), and is capped at the same 48-char
                // limit as Value names.
                guard line.range(of: "^\\w+$", options: .regularExpression) != nil,
                      line.count <= 48,
                      TextFSMLineOp(rawValue: line) == nil,
                      TextFSMRecordOp(rawValue: line) == nil else {
                    throw TextFSMTemplateError.invalidStateName(name: line, lineNumber: lineNumber)
                }
                // Mirrors textfsm's `if state_name in self.states: raise
                // ...` — silently merging two separately-declared state
                // blocks with the same name (as an earlier version of this
                // file did) hides what's almost certainly a template typo.
                guard states[line] == nil else {
                    throw TextFSMTemplateError.duplicateStateName(name: line, lineNumber: lineNumber)
                }
                states[line] = []
                currentState = line
            }
        }

        guard states["Start"] != nil else {
            throw TextFSMTemplateError.missingStartState
        }
        for (stateName, rules) in states {
            if (stateName == "End" || stateName == "EOF"), !rules.isEmpty {
                throw TextFSMTemplateError.terminalStateNotEmpty(state: stateName)
            }
            for rule in rules {
                guard rule.lineOp != .error, !rule.newState.isEmpty else { continue }
                guard rule.newState == "End" || rule.newState == "EOF" || states[rule.newState] != nil else {
                    throw TextFSMTemplateError.unknownNewState(state: rule.newState, fromState: stateName)
                }
            }
        }

        self.values = parsedValues
        self.states = states
    }

    private static let commentRegex = try! NSRegularExpression(pattern: #"^\s*#"#)

    private static func isComment(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return commentRegex.firstMatch(in: line, range: range) != nil
    }

    /// Exactly textfsm's own indentation rule: a rule line must start with
    /// ONE space, TWO spaces, or a tab before the '^' — not three or more.
    /// Real ntc-templates files consistently use two-space indentation, so
    /// this rarely bites, but it's reproduced exactly rather than loosened.
    private static func looksLikeRuleLine(_ line: String) -> Bool {
        line.hasPrefix(" ^") || line.hasPrefix("  ^") || line.hasPrefix("\t^")
    }
}
