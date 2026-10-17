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
//  TextFSMIndexTable.swift
//  Swiftmiko
//
//  Faithful port of Google textfsm's IndexTable/CliTable.GetRowMatch —
//  maps a (platform, command) pair to a template filename using
//  ntc-templates' own `index` file, unmodified. Matches the real parsing
//  quirks on purpose: a naive comma split (no CSV quoting), silently
//  dropped malformed rows, first-match-wins in file order (so the real
//  index file's documented row ordering — longer/more specific template
//  names before shorter ones for the same platform — is load-bearing,
//  not cosmetic), and Python re.match's "anchored at start, not at end"
//  semantics for each compiled column.
//

import Foundation

public enum TextFSMIndexError: Error, CustomStringConvertible, Sendable {
    case indexFileNotFound(String)
    case missingTemplateColumn
    case noTemplateFound(platform: String, command: String)
    case multiTemplateRowNotSupported(templates: [String])

    public var description: String {
        switch self {
        case .indexFileNotFound(let path):
            return "TextFSM index file not found: \(path)"
        case .missingTemplateColumn:
            return "Index file does not have a 'Template' column."
        case .noTemplateFound(let platform, let command):
            return "No template found for platform \"\(platform)\" and command \"\(command)\"."
        case .multiTemplateRowNotSupported(let templates):
            return "Index row maps to multiple templates (\(templates.joined(separator: ":"))) — " +
                "merging several TextFSM tables for one command isn't implemented. " +
                "Pass an explicit template: path for one of them instead."
        }
    }
}

final class TextFSMIndexTable {
    private struct Row {
        let template: String
        let compiledColumns: [String: NSRegularExpression]
    }

    private let rows: [Row]

    init(contents: String) throws {
        let lines = contents.components(separatedBy: .newlines)

        var headerColumns: [String] = []
        var bodyStartIndex = 0
        while bodyStartIndex < lines.count {
            let withoutComment = lines[bodyStartIndex].split(
                separator: "#", maxSplits: 1, omittingEmptySubsequences: false
            )[0]
            let stripped = withoutComment.trimmingCharacters(in: .whitespaces)
            bodyStartIndex += 1
            if !stripped.isEmpty {
                headerColumns = stripped
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                break
            }
        }
        guard headerColumns.contains("Template") else {
            throw TextFSMIndexError.missingTemplateColumn
        }

        var parsedRows: [Row] = []
        for line in lines[bodyStartIndex...] {
            if line.hasPrefix("#") { continue }
            let fields = line
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // Silently drop malformed lines (blank lines, wrong field count) —
            // matches texttable.CsvToTable's own behavior exactly.
            guard fields.count == headerColumns.count else { continue }

            var templateValue = ""
            var compiled: [String: NSRegularExpression] = [:]
            for (column, rawValue) in zip(headerColumns, fields) {
                if column == "Template" {
                    templateValue = rawValue
                    continue
                }
                let value = column == "Command" ? Self.expandCompletion(rawValue) : rawValue
                guard !value.isEmpty else { continue }  // empty column = wildcard
                compiled[column] = try NSRegularExpression(pattern: value)
            }
            parsedRows.append(Row(template: templateValue, compiledColumns: compiled))
        }
        self.rows = parsedRows
    }

    convenience init(filePath: String) throws {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw TextFSMIndexError.indexFileNotFound(filePath)
        }
        let contents = try String(contentsOfFile: filePath, encoding: .utf8)
        try self.init(contents: contents)
    }

    func template(forPlatform platform: String, command: String) throws -> String {
        let attributes = ["Command": command, "Platform": platform]
        for row in rows {
            var allMatch = true
            for (key, value) in attributes {
                guard let regex = row.compiledColumns[key] else { continue }
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                guard let match = regex.firstMatch(in: value, range: range),
                      match.range.location == 0 else {
                    allMatch = false
                    break
                }
            }
            if allMatch {
                return row.template
            }
        }
        throw TextFSMIndexError.noTemplateFound(platform: platform, command: command)
    }

    /// Expands `abc[[xyz]]` into `abc(x(y(z)?)?)?` — ntc-templates' own
    /// variable-length command completion syntax. Multiple `[[...]]` groups
    /// within one Command string expand independently. Requires at least
    /// one character inside the brackets, matching textfsm's own
    /// `\[\[.+?\]\]` (empty `[[]]` is left untouched, same as upstream).
    static func expandCompletion(_ pattern: String) -> String {
        var result = ""
        var remainder = Substring(pattern)
        while let openRange = remainder.range(of: "[[") {
            guard let closeRange = remainder.range(
                of: "]]", range: openRange.upperBound..<remainder.endIndex
            ) else {
                result += remainder
                return result
            }
            let word = remainder[openRange.upperBound..<closeRange.lowerBound]
            guard !word.isEmpty else {
                result += remainder[remainder.startIndex..<closeRange.upperBound]
                remainder = remainder[closeRange.upperBound...]
                continue
            }
            result += remainder[remainder.startIndex..<openRange.lowerBound]
            result += "(" + word.map(String.init).joined(separator: "(")
            result += String(repeating: ")?", count: word.count)
            remainder = remainder[closeRange.upperBound...]
        }
        result += remainder
        return result
    }
}
