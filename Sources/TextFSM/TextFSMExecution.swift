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
//  TextFSMExecution.swift
//  Swiftmiko
//
//  Port of textfsm.parser.TextFSM's run loop: ParseText/_CheckLine driving
//  the state machine one input line at a time, plus _AppendRecord's
//  Required/List/all-blank-row handling.
//

import Foundation

extension TextFSMTemplate {
    /// Runs this template against `text`, returning one dictionary per
    /// recorded row — matches textfsm's `ParseTextToDicts`. Dictionary
    /// values are `String` for plain values, or `[Any]` (of `String` /
    /// `[String: String]` elements) for `List`-typed values.
    public func parseTextToDicts(_ text: String) throws -> [[String: Any]] {
        for value in values { value.clearAllVar() }

        var lines = text.components(separatedBy: "\n")
        lines = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

        var results: [[TextFSMCell]] = []
        var currentStateName = "Start"
        var currentRules = states["Start"] ?? []

        func appendRecord() throws {
            guard !values.isEmpty else { return }
            var row: [TextFSMCell] = []
            do {
                for value in values {
                    row.append(try value.onSaveRecord())
                }
            } catch is TextFSMSkipRecord {
                for value in values { value.clearVar() }
                return
            }

            let allEmpty = row.allSatisfy { cell in
                switch cell {
                case .unset: return true
                case .list(let l): return l.isEmpty
                case .text: return false
                }
            }
            if !allEmpty {
                results.append(row)
            }
            for value in values { value.clearVar() }
        }

        /// Mirrors `Fillup.OnAssignVar`: walk already-recorded rows in
        /// reverse, backfilling this column until a non-empty entry stops
        /// the walk.
        func fillUp(valueIndex: Int, text: String) {
            guard !text.isEmpty else { return }
            for rowIndex in results.indices.reversed() {
                switch results[rowIndex][valueIndex] {
                case .unset:
                    results[rowIndex][valueIndex] = .text(text)
                case .list(let entries) where entries.isEmpty:
                    results[rowIndex][valueIndex] = .text(text)
                default:
                    return
                }
            }
        }

        lineLoop: for rawLine in lines {
            let fullRange = NSRange(rawLine.startIndex..., in: rawLine)

            var ruleIndex = 0
            while ruleIndex < currentRules.count {
                let rule = currentRules[ruleIndex]
                ruleIndex += 1

                guard let match = rule.regex.firstMatch(in: rawLine, range: fullRange),
                      match.range.location == 0 else { continue }

                for groupName in rule.namedGroupNames {
                    let groupRange = match.range(withName: groupName)
                    guard groupRange.location != NSNotFound,
                          let swiftRange = Range(groupRange, in: rawLine) else { continue }
                    guard let valueIndex = values.firstIndex(where: { $0.name == groupName }) else { continue }
                    let text = String(rawLine[swiftRange])
                    values[valueIndex].assign(text)
                    if values[valueIndex].options.contains(.fillup) {
                        fillUp(valueIndex: valueIndex, text: text)
                    }
                }

                if rule.lineOp == .error {
                    let message = rule.newState.isEmpty ? "State Error" : rule.newState
                    throw TextFSMRuntimeError.templateDefinedError(
                        message: message, lineNumber: rule.lineNumber, inputLine: rawLine
                    )
                }

                switch rule.recordOp {
                case .record: try appendRecord()
                case .clear: for v in values { v.clearVar() }
                case .clearall: for v in values { v.clearAllVar() }
                case .noRecord: break
                }

                if !rule.newState.isEmpty {
                    currentStateName = rule.newState
                    currentRules = (rule.newState == "End" || rule.newState == "EOF")
                        ? []
                        : (states[rule.newState] ?? [])
                }

                if rule.lineOp != .continue {
                    break
                }
                // Continue: fall through to the next rule index against
                // this SAME input line, not the start of currentRules and
                // not the next input line.
            }

            if currentStateName == "End" || currentStateName == "EOF" {
                break lineLoop
            }
        }

        // Implicit EOF: if the template never declares its own 'EOF'
        // state and processing didn't explicitly end via 'End', record
        // whatever's pending — matches textfsm's own implicit
        // Next.Record at end of input.
        if currentStateName != "End", states["EOF"] == nil {
            try appendRecord()
        }

        let names = header
        return results.map { row in
            var dict: [String: Any] = [:]
            for (index, cell) in row.enumerated() {
                switch cell {
                case .unset:
                    dict[names[index]] = ""
                case .text(let s):
                    dict[names[index]] = s
                case .list(let entries):
                    dict[names[index]] = entries.map { entry -> Any in
                        switch entry {
                        case .text(let s): return s
                        case .fields(let f): return f
                        }
                    }
                }
            }
            return dict
        }
    }
}
