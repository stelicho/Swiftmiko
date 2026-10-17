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
//  TTPErrors.swift
//  Swiftmiko
//

import Foundation

public enum TTPParsingError: Error, CustomStringConvertible, Sendable {
    case unsupportedTag(String)
    case unclosedGroup(String)
    case unexpectedGroupClose
    case unsupportedFormatter(String)
    case malformedVariableToken(String)

    public var description: String {
        switch self {
        case .unsupportedTag(let tag):
            return "Unsupported TTP tag <\(tag)>. This is a core-subset native TTP engine: " +
                "only <group> is implemented (no <vars>, <template>, lookup tables, outputs, " +
                "savers, or macros)."
        case .unclosedGroup(let name):
            return "TTP template has an unclosed <group name=\"\(name)\"> (missing </group>)."
        case .unexpectedGroupClose:
            return "TTP template has a </group> with no matching open <group>."
        case .unsupportedFormatter(let name):
            return "Unsupported TTP formatter \"\(name)\". This core-subset engine only " +
                "implements ORPHRASE, DIGIT, WORD, and IP."
        case .malformedVariableToken(let token):
            return "Malformed TTP variable token: \(token)"
        }
    }
}
