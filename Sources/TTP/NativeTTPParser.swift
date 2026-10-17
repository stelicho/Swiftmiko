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
//  NativeTTPParser.swift
//  Swiftmiko
//
//  Bridges the native TTP engine (TTPTemplate/TTPExecution) to the
//  TTPParserAdapter protocol declared in Utilities.swift, so it plugs
//  directly into getStructuredDataTTP()/structuredDataConverter() the
//  same way NativeTextFSMParser does for TextFSM.
//
//  Core subset only: <group> tags (with nesting and the trailing-"*"
//  list marker) and {{ variable }} / {{ variable | FORMATTER }}
//  extraction, where FORMATTER is one of ORPHRASE, DIGIT, WORD, or IP.
//  No macros, outputs/savers, lookup tables, or Jinja2 templating —
//  see COMMON_ISSUES.md for why macros in particular aren't planned
//  (they're arbitrary embedded Python with no honest Swift analog).
//

import Foundation

public enum NativeTTPParserError: Error, CustomStringConvertible, Sendable {
    case templateFileNotFound(String)

    public var description: String {
        switch self {
        case .templateFileNotFound(let path):
            return "TTP template file not found: \(path)"
        }
    }
}

/// Concrete `TTPParserAdapter` backed by the native Swift TTP engine.
/// `template` is a file path (same convention as `NativeTextFSMParser`),
/// not inline template text.
public final class NativeTTPParser: TTPParserAdapter {
    public init() {}

    public func parse(rawOutput: String, template: String) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: template) else {
            throw NativeTTPParserError.templateFileNotFound(template)
        }
        let templateString = try String(contentsOfFile: template, encoding: .utf8)
        let parsedTemplate = try TTPTemplate(templateString: templateString)
        return TTPExecution.parse(template: parsedTemplate, rawText: rawOutput)
    }
}
