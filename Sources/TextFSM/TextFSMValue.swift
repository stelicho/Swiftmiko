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
//  TextFSMValue.swift
//  Swiftmiko
//
//  Port of textfsm.parser.TextFSMValue and its Required/Filldown/Fillup/
//  Key/List options.
//
//  Options are stored in DECLARATION ORDER, not as an unordered set —
//  that order is load-bearing upstream. `Required` inspects whatever the
//  value currently holds at the point it runs during OnSaveRecord, so
//  "Value Required,List ..." and "Value List,Required ..." are NOT
//  equivalent in real textfsm (the former can see a stale/empty scalar
//  before List has had a chance to install the accumulated list). This
//  file reproduces that sequential-mutation model exactly rather than
//  quietly "fixing" what looks like a footgun.
//

import Foundation

enum TextFSMValueOption: String {
    case required = "Required"
    case filldown = "Filldown"
    case fillup = "Fillup"
    case key = "Key"
    case list = "List"
}

/// A single entry recorded for a `List`-typed value: either the matched
/// text itself, or — when the value's own regex has nested named groups —
/// a dictionary of those sub-fields. Mirrors textfsm's
/// `TextFSMOptions.List.OnAssignVar`, which re-matches the just-captured
/// text against the value's own compiled regex looking for a groupdict.
public enum TextFSMListEntry: Equatable, Sendable {
    case text(String)
    case fields([String: String])
}

/// What a value contributes to a row once `OnSaveRecord` has run — mirrors
/// Python's distinction between a scalar `None` and an empty list `[]`,
/// both of which count as "empty" for the all-blank-row check in
/// `_AppendRecord`, but which otherwise behave differently.
enum TextFSMCell: Equatable {
    case unset
    case text(String)
    case list([TextFSMListEntry])
}

final class TextFSMValue {
    let name: String
    let rawRegex: String
    /// `rawRegex` with the outer wrapping `(` turned into a named capture
    /// group — mirrors Python's `re.sub(r'^\(', '(?P<name>', self.regex)`,
    /// translated to ICU's `(?<name>...)` syntax for NSRegularExpression.
    let template: String
    let options: [TextFSMValueOption]
    let lineNumber: Int

    /// Only populated for `List`-typed values whose own regex has nested
    /// named groups beyond the mandatory outer one — used to re-extract
    /// those sub-fields from the captured text at assignment time.
    private let nestedGroupRegex: NSRegularExpression?

    private(set) var scalar: String?
    private(set) var list: [TextFSMListEntry] = []
    private var filldownSaved: String?

    init(line: String, lineNumber: Int) throws {
        self.lineNumber = lineNumber

        // Python: `value_line = value.split(' ')` — a literal single-space
        // split (not whitespace-collapsing), preserved exactly since it's
        // how upstream disambiguates "no options" (token[2] starts with
        // '(') from "options present" (token[2] is the name instead).
        let tokens = line.components(separatedBy: " ")
        guard tokens.count >= 3 else {
            throw TextFSMTemplateError.malformedValueLine(line: line, lineNumber: lineNumber)
        }

        let name: String
        let regex: String
        var options: [TextFSMValueOption] = []

        if !tokens[2].hasPrefix("(") {
            for optionToken in tokens[1].components(separatedBy: ",") where !optionToken.isEmpty {
                guard let option = TextFSMValueOption(rawValue: optionToken) else {
                    throw TextFSMTemplateError.unknownOption(option: optionToken, lineNumber: lineNumber)
                }
                options.append(option)
            }
            name = tokens[2]
            regex = tokens[3...].joined(separator: " ")
        } else {
            name = tokens[1]
            regex = tokens[2...].joined(separator: " ")
        }

        guard name.count <= 48,
              name.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else {
            throw TextFSMTemplateError.invalidValueName(name: name, lineNumber: lineNumber)
        }

        let regexChars = Array(regex)
        guard regexChars.count >= 2, regexChars.first == "(", regexChars.last == ")",
              regexChars[regexChars.count - 2] != "\\" else {
            throw TextFSMTemplateError.regexNotParenthesized(regex: regex, lineNumber: lineNumber)
        }

        let icuRegex = Self.translatePythonRegexSyntax(regex)
        guard let compiled = try? NSRegularExpression(pattern: icuRegex) else {
            throw TextFSMTemplateError.invalidRegex(regex: regex, lineNumber: lineNumber)
        }

        self.name = name
        self.rawRegex = regex
        self.options = options
        self.template = "(?<\(name)>" + icuRegex.dropFirst()

        if options.contains(.list), compiled.numberOfCaptureGroups > 0 {
            self.nestedGroupRegex = compiled
        } else {
            self.nestedGroupRegex = nil
        }
    }

    /// Translates the handful of Python `re` syntax forms textfsm
    /// templates actually rely on into ICU/NSRegularExpression syntax.
    /// Named groups are the one real difference that matters here:
    /// Python's `(?P<name>...)`, ICU's `(?<name>...)`.
    static func translatePythonRegexSyntax(_ pattern: String) -> String {
        pattern.replacingOccurrences(of: "(?P<", with: "(?<")
    }

    var isRequired: Bool { options.contains(.required) }
    var isKey: Bool { options.contains(.key) }
    var isList: Bool { options.contains(.list) }

    // MARK: Lifecycle — mirrors AssignVar/ClearVar/ClearAllVar/OnSaveRecord

    /// Mirrors `TextFSMValue.AssignVar` plus the `List`/`Filldown` option
    /// hooks. `Fillup` is handled by the owning template/interpreter
    /// instead, since it needs access to every previously-recorded row.
    func assign(_ matchedText: String) {
        scalar = matchedText
        for option in options {
            switch option {
            case .filldown:
                filldownSaved = scalar
            case .list:
                if let nestedGroupRegex {
                    let full = NSRange(matchedText.startIndex..., in: matchedText)
                    if let match = nestedGroupRegex.firstMatch(in: matchedText, range: full),
                       match.range.location == 0 {
                        var fields: [String: String] = [:]
                        for groupName in nestedGroupRegex.swiftmikoNamedGroupNames() {
                            let r = match.range(withName: groupName)
                            guard r.location != NSNotFound, let swiftRange = Range(r, in: matchedText) else { continue }
                            fields[groupName] = String(matchedText[swiftRange])
                        }
                        if !fields.isEmpty {
                            list.append(.fields(fields))
                            continue
                        }
                    }
                }
                list.append(.text(matchedText))
            case .fillup, .required, .key:
                break
            }
        }
    }

    /// Mirrors `ClearVar` — the "soft" reset performed after a `Record`,
    /// which `Filldown` (and, transitively, a `Filldown`+`List` value)
    /// survives.
    func clearVar() {
        scalar = nil
        for option in options {
            switch option {
            case .filldown:
                scalar = filldownSaved
            case .list:
                if !options.contains(.filldown) {
                    list = []
                }
            case .fillup, .required, .key:
                break
            }
        }
    }

    /// Mirrors `ClearAllVar` — the hard reset used at parse start and for
    /// an explicit `Clearall` rule action. Wipes `Filldown`'s saved state
    /// too, unlike `clearVar()`.
    func clearAllVar() {
        scalar = nil
        for option in options {
            switch option {
            case .filldown:
                filldownSaved = nil
            case .list:
                list = []
            case .fillup, .required, .key:
                break
            }
        }
    }

    /// Mirrors every option's `OnSaveRecord` hook running in declaration
    /// order against a single mutable "current value" — exactly how
    /// upstream's `Required` can observe a stale scalar if it's declared
    /// before `List` on the same Value line.
    func onSaveRecord() throws -> TextFSMCell {
        enum Current { case none, text(String), list([TextFSMListEntry]) }
        var current: Current = scalar.map { .text($0) } ?? .none

        for option in options {
            switch option {
            case .required:
                let isEmpty: Bool
                switch current {
                case .none: isEmpty = true
                case .text(let s): isEmpty = s.isEmpty
                case .list(let l): isEmpty = l.isEmpty
                }
                if isEmpty { throw TextFSMSkipRecord() }
            case .list:
                current = .list(list)
            case .filldown, .fillup, .key:
                break
            }
        }

        switch current {
        case .none: return .unset
        case .text(let s): return .text(s)
        case .list(let l): return .list(l)
        }
    }
}

extension NSRegularExpression {
    private static let namedGroupExtractor = try! NSRegularExpression(pattern: #"\(\?<([A-Za-z0-9_]+)>"#)

    /// Foundation exposes no public API to enumerate a compiled regex's
    /// named groups, so this re-scans the original pattern text (which
    /// `NSRegularExpression.pattern` always returns verbatim) for
    /// `(?<name>` occurrences instead.
    func swiftmikoNamedGroupNames() -> [String] {
        let range = NSRange(pattern.startIndex..., in: pattern)
        return Self.namedGroupExtractor.matches(in: pattern, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: pattern) else { return nil }
            return String(pattern[r])
        }
    }
}
