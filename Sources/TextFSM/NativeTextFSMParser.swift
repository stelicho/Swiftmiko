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
//  When no explicit template is given, platform+command -> template
//  auto-selection uses ntc-templates' own `index` file via
//  TextFSMIndexTable — the same mechanism Netmiko's CliTable/ntc_templates
//  use — located the same way Netmiko finds it (NET_TEXTFSM env var, or
//  ~/ntc-templates/ntc_templates/templates, via getTemplateDirectory()).
//

import Foundation

public enum NativeTextFSMParserError: Error, CustomStringConvertible, Sendable {
    case noTemplateSpecified
    case templateFileNotFound(String)

    public var description: String {
        switch self {
        case .noTemplateSpecified:
            return "NativeTextFSMParser requires either an explicit template file path " +
                "or both platform and command for index-based auto-selection."
        case .templateFileNotFound(let path):
            return "TextFSM template file not found: \(path)"
        }
    }
}

/// Concrete `TextFSMParserAdapter` backed by the native Swift TextFSM
/// engine — no Python, no shelling out, works directly against real
/// ntc-templates `.textfsm` files.
public final class NativeTextFSMParser: TextFSMParserAdapter {
    private static let indexCacheLock = NSLock()
    private static var indexCache: [String: TextFSMIndexTable] = [:]

    public init() {}

    public func parse(
        rawOutput: String,
        platform: String?,
        command: String?,
        template: String?
    ) throws -> [[String: Any]] {
        let templatePath: String
        if let template {
            templatePath = template
        } else {
            guard let platform, let command else {
                throw NativeTextFSMParserError.noTemplateSpecified
            }
            let directory = try getTemplateDirectory()
            let index = try Self.cachedIndex(templateDirectory: directory)
            let resolved = try index.template(forPlatform: platform, command: command)
            templatePath = "\(directory)/\(try Self.resolveSingleTemplateName(resolved))"
        }
        guard FileManager.default.fileExists(atPath: templatePath) else {
            throw NativeTextFSMParserError.templateFileNotFound(templatePath)
        }
        let templateString = try String(contentsOfFile: templatePath, encoding: .utf8)
        let parsedTemplate = try TextFSMTemplate(templateString: templateString)
        return try parsedTemplate.parseTextToDicts(rawOutput)
    }

    /// An index row's Template column is colon-separated when ntc-templates
    /// wants several tables joined for one command (e.g. multiple `show
    /// module` variants) — rejected explicitly rather than silently
    /// merged or dropped, since that join isn't implemented.
    static func resolveSingleTemplateName(_ resolved: String) throws -> String {
        let names = resolved.split(separator: ":").map(String.init)
        guard names.count == 1 else {
            throw TextFSMIndexError.multiTemplateRowNotSupported(templates: names)
        }
        return names[0]
    }

    /// Index files are parsed once per template directory and reused —
    /// matches CliTable's own class-level `INDEX` cache, since ntc-templates'
    /// real index file has ~1000 rows and is otherwise re-parsed on every call.
    private static func cachedIndex(templateDirectory: String) throws -> TextFSMIndexTable {
        indexCacheLock.lock()
        defer { indexCacheLock.unlock() }
        if let cached = indexCache[templateDirectory] {
            return cached
        }
        let index = try TextFSMIndexTable(filePath: "\(templateDirectory)/index")
        indexCache[templateDirectory] = index
        return index
    }
}
