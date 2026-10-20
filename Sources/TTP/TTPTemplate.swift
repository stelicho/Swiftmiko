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
//  TTPTemplate.swift
//  Swiftmiko
//
//  Core-subset native port of ttp (Template Text Parser): <group> tags
//  (including nesting and the trailing-`*` list-output marker) and
//  `{{ variable }}` / `{{ variable | FORMATTER }}` extraction, verified
//  against the real `ttp` Python package's actual behavior rather than
//  its docs alone (e.g. the "*" suffix only forces list output when a
//  group matches exactly once — multiple matches are always a list
//  regardless — and nested groups are entirely tag-driven, not
//  indentation-driven).
//
//  Deliberately NOT implemented: macros (arbitrary embedded Python —
//  no honest Swift equivalent), outputs/savers, lookup tables, and
//  Jinja2-style dynamic templating. Any other tag throws a clear error
//  instead of silently mis-parsing.
//

import Foundation

enum TTPFormatter {
    /// Real patterns from ttp's own `patterns/get_pattern.py`, not
    /// reconstructed from documentation.
    private static let word = "\\S+"
    private static let orphrase = "\\S+|(?:\\S+ )+?\\S+"
    private static let digit = "\\d+"
    private static let ip = "(?:[0-9]{1,3}\\.){3}[0-9]{1,3}"

    static func pattern(for name: String?) throws -> String {
        guard let name else { return word }
        switch name {
        case "WORD": return word
        case "ORPHRASE": return orphrase
        case "DIGIT": return digit
        case "IP": return ip
        default: throw TTPParsingError.unsupportedFormatter(name)
        }
    }
}

struct TTPLineMatcher {
    let regex: NSRegularExpression
    let nameMapping: [String: String]  // ICU-safe synthetic name -> real variable name
    let groupPath: [String]            // group names from root to this line's owning group
}

public final class TTPTemplate {
    let matchers: [TTPLineMatcher]
    /// Keyed by "/"-joined group path. True when that group's name ended
    /// in "*" (always list output, even for a single match).
    let forceListByPath: [String: Bool]

    public init(templateString: String) throws {
        var matchers: [TTPLineMatcher] = []
        var forceListByPath: [String: Bool] = [:]
        var pathStack: [String] = []

        for rawLine in templateString.components(separatedBy: .newlines) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
                if trimmed == "</group>" {
                    guard !pathStack.isEmpty else { throw TTPParsingError.unexpectedGroupClose }
                    pathStack.removeLast()
                    continue
                }
                if let name = Self.parseGroupOpenTag(trimmed) {
                    let baseName = name.hasSuffix("*") ? String(name.dropLast()) : name
                    pathStack.append(baseName)
                    forceListByPath[pathStack.joined(separator: "/")] = name.hasSuffix("*")
                    continue
                }
                throw TTPParsingError.unsupportedTag(Self.extractTagName(trimmed))
            }

            matchers.append(try Self.compileLine(line, groupPath: pathStack))
        }
        guard pathStack.isEmpty else {
            throw TTPParsingError.unclosedGroup(pathStack.last!)
        }
        self.matchers = matchers
        self.forceListByPath = forceListByPath
    }

    private static func extractTagName(_ trimmedLine: String) -> String {
        let withoutBrackets = trimmedLine.trimmingCharacters(in: CharacterSet(charactersIn: "<>/"))
        return withoutBrackets.split(separator: " ").first.map(String.init) ?? withoutBrackets
    }

    /// Returns the group's `name` attribute (including a trailing `*` if
    /// present) for a `<group name="...">` opening tag, or nil if `trimmedLine`
    /// isn't a well-formed group-open tag.
    private static func parseGroupOpenTag(_ trimmedLine: String) -> String? {
        guard trimmedLine.hasPrefix("<group"), !trimmedLine.hasPrefix("</") else { return nil }
        guard let nameRange = trimmedLine.range(
            of: "name\\s*=\\s*\"([^\"]*)\"", options: .regularExpression
        ) else { return nil }
        let nameAttr = trimmedLine[nameRange]
        guard let quoteStart = nameAttr.firstIndex(of: "\""),
              let quoteEnd = nameAttr.lastIndex(of: "\""), quoteStart != quoteEnd else { return nil }
        return String(nameAttr[nameAttr.index(after: quoteStart)..<quoteEnd])
    }

    /// Builds a `^...$`-anchored full-line regex: literal text escaped,
    /// each `{{ name }}` / `{{ name | FORMATTER }}` token replaced with a
    /// named capture group. Real ttp requires the whole line to match
    /// (confirmed empirically — neither leading nor trailing unmatched
    /// text is tolerated), not a free substring search.
    private static func compileLine(_ rawLine: String, groupPath: [String]) throws -> TTPLineMatcher {
        var pattern = "^"
        var remainder = Substring(rawLine)
        while let openRange = remainder.range(of: "{{") {
            pattern += NSRegularExpression.escapedPattern(for: String(remainder[remainder.startIndex..<openRange.lowerBound]))
            guard let closeRange = remainder.range(of: "}}", range: openRange.upperBound..<remainder.endIndex) else {
                throw TTPParsingError.malformedVariableToken(String(remainder))
            }
            let token = remainder[openRange.upperBound..<closeRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let parts = token.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            // Real ttp's variable-name grammar is far looser than a
            // Swift/Python identifier: confirmed empirically (installed
            // `ttp` package) that digit-first names ("1abc"), hyphens
            // ("a-b"), and dots ("a.b.c", even leading/trailing dots) are
            // all accepted verbatim as the literal output key — only an
            // empty name or internal whitespace actually fails. The
            // sanitize/remap machinery below already handles embedding an
            // arbitrary name into a regex named group and recovering it
            // afterward, so there's no reason to be stricter than real ttp
            // actually is here.
            guard let varName = parts.first, !varName.isEmpty,
                  varName.range(of: "\\s", options: .regularExpression) == nil else {
                throw TTPParsingError.malformedVariableToken(token)
            }
            let formatterPattern = try TTPFormatter.pattern(for: parts.count > 1 ? parts[1] : nil)
            pattern += "(?<\(varName)>\(formatterPattern))"
            remainder = remainder[closeRange.upperBound...]
        }
        pattern += NSRegularExpression.escapedPattern(for: String(remainder))
        pattern += "$"

        let (sanitized, mapping) = TextFSMRegexSupport.sanitizeNamedGroups(in: pattern)
        let regex = try NSRegularExpression(pattern: sanitized)
        return TTPLineMatcher(regex: regex, nameMapping: mapping, groupPath: groupPath)
    }
}
