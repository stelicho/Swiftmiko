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
//  TextFSMErrors.swift
//  Swiftmiko
//
//  Native Swift port of Google's textfsm (github.com/google/textfsm).
//  Error types raised while parsing a template (TextFSMTemplateError,
//  matching Python's exception of the same name) versus while running
//  a template against real input text (TextFSMRuntimeError, matching
//  an explicit `Error` rule firing).
//

import Foundation

public enum TextFSMTemplateError: Error, CustomStringConvertible, Sendable {
    case malformedValueLine(line: String, lineNumber: Int)
    case invalidValueName(name: String, lineNumber: Int)
    case unknownOption(option: String, lineNumber: Int)
    case duplicateOption(option: String, lineNumber: Int)
    case regexNotParenthesized(regex: String, lineNumber: Int)
    case invalidRegex(regex: String, lineNumber: Int)
    case malformedRuleLine(line: String, lineNumber: Int)
    case missingRuleIndentation(line: String, lineNumber: Int)
    case continueWithNewState(lineNumber: Int)
    case invalidStateName(name: String, lineNumber: Int)
    case duplicateValueName(name: String, lineNumber: Int)
    case duplicateStateName(name: String, lineNumber: Int)
    case unknownNewState(state: String, fromState: String)
    case terminalStateNotEmpty(state: String)
    case missingStartState
    case variableSubstitutionFailed(text: String, lineNumber: Int)

    public var description: String {
        switch self {
        case .malformedValueLine(let line, let n):
            return "Line \(n): expected at least 3 tokens in Value declaration: '\(line)'"
        case .invalidValueName(let name, let n):
            return "Line \(n): invalid Value name '\(name)' or name too long"
        case .unknownOption(let option, let n):
            return "Line \(n): unknown Value option '\(option)'"
        case .duplicateOption(let option, let n):
            return "Line \(n): duplicate option \"\(option)\""
        case .regexNotParenthesized(let regex, let n):
            return "Line \(n): Value regex '\(regex)' must be contained within a '()' pair"
        case .invalidRegex(let regex, let n):
            return "Line \(n): invalid regular expression '\(regex)'"
        case .malformedRuleLine(let line, let n):
            return "Line \(n): badly formatted rule '\(line)'"
        case .missingRuleIndentation(let line, let n):
            return "Line \(n): missing white space or caret ('^') before rule: '\(line)'"
        case .continueWithNewState(let n):
            return "Line \(n): 'Continue' line operator cannot specify a new state"
        case .invalidStateName(let name, let n):
            return "Line \(n): invalid state name '\(name)' — alphanumeric characters only"
        case .duplicateValueName(let name, let n):
            return "Line \(n): duplicate declarations for Value '\(name)'"
        case .duplicateStateName(let name, let n):
            return "Line \(n): duplicate state name '\(name)'"
        case .unknownNewState(let state, let from):
            return "State '\(state)' not found, referenced in state '\(from)'"
        case .terminalStateNotEmpty(let state):
            return "'\(state)' state must be empty"
        case .missingStartState:
            return "Missing 'Start' state"
        case .variableSubstitutionFailed(let text, let n):
            return "Line \(n): duplicate or invalid variable substitution in '\(text)'"
        }
    }
}

/// Raised when an `Error` rule actually fires against real input — distinct
/// from TextFSMTemplateError, which covers mistakes in the template itself.
public enum TextFSMRuntimeError: Error, CustomStringConvertible, Sendable {
    case templateDefinedError(message: String, lineNumber: Int, inputLine: String)

    public var description: String {
        switch self {
        case .templateDefinedError(let message, let lineNumber, let inputLine):
            return "Error: \(message). Rule Line: \(lineNumber). Input Line: \(inputLine)."
        }
    }
}

/// Internal control-flow signal — mirrors Python's `SkipRecord` exception
/// raised by the `Required` option. Never surfaces to callers.
struct TextFSMSkipRecord: Error {}
