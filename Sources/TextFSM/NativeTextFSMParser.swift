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
//  NativeTextFSMParser.swift
//  Swiftmiko
//
//  Bridges the native TextFSM engine (TextFSMTemplate/TextFSMExecution)
//  to the TextFSMParserAdapter protocol declared in Utilities.swift, so
//  it plugs directly into getStructuredDataTextFSM()/structuredDataConverter().
//
//  Scope note: this phase only supports an explicit template file path —
//  the platform+command -> template auto-selection ntc-templates' own
//  `index` file provides (the same mechanism Netmiko's CliTable uses) is
//  not implemented yet. Passing platform/command without an explicit
//  template throws a clear error rather than silently guessing.
//

import Foundation

public enum NativeTextFSMParserError: Error, CustomStringConvertible, Sendable {
    case noTemplateSpecified
    case templateFileNotFound(String)

    public var description: String {
        switch self {
        case .noTemplateSpecified:
            return "NativeTextFSMParser requires an explicit template file path. " +
                "platform/command -> template auto-selection (ntc-templates' index file) " +
                "is not implemented yet."
        case .templateFileNotFound(let path):
            return "TextFSM template file not found: \(path)"
        }
    }
}

/// Concrete `TextFSMParserAdapter` backed by the native Swift TextFSM
/// engine — no Python, no shelling out, works directly against real
/// ntc-templates `.textfsm` files.
public final class NativeTextFSMParser: TextFSMParserAdapter {
    public init() {}

    public func parse(
        rawOutput: String,
        platform: String?,
        command: String?,
        template: String?
    ) throws -> [[String: Any]] {
        guard let templatePath = template else {
            throw NativeTextFSMParserError.noTemplateSpecified
        }
        guard FileManager.default.fileExists(atPath: templatePath) else {
            throw NativeTextFSMParserError.templateFileNotFound(templatePath)
        }
        let templateString = try String(contentsOfFile: templatePath, encoding: .utf8)
        let parsedTemplate = try TextFSMTemplate(templateString: templateString)
        return try parsedTemplate.parseTextToDicts(rawOutput)
    }
}
