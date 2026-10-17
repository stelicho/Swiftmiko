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
//  TextFSMIndexTableTests.swift
//  SwiftmikoTests
//
//  The fixture below is a real, unmodified slice of ntc-templates'
//  own `index` file (header block verbatim, plus five real rows kept
//  in their real relative file order) — not a simplified rewrite.
//

import XCTest
@testable import Swiftmiko

#if os(Windows)
import ucrt
#endif

final class TextFSMIndexTableTests: XCTestCase {
    // swiftlint:disable:next line_length
    private static let realIndexSlice = #"""
    # First line is the header fields for columns and is mandatory.
    # Regular expressions are supported in all fields except the first.
    # Last field supports variable length command completion.
    # abc[[xyz]] is expanded to abc(x(y(z)?)?)?, regexp inside [[]] is not supported
    #
    # Rules of Ordering:
    #  - OS in alphabetical order
    #  - Template name in length order (longest to shortest)
    #  - When Length is the same, use alphabetical order
    #  - Keep space between OS's
    #
    Template, Hostname, Platform, Command

    cisco_asa_show_arp.textfsm, .*, cisco_(asa|ftd), sh[[ow]] arp
    cisco_ios_show_module.textfsm:cisco_ios_show_module_status.textfsm:cisco_ios_show_module_submodule.textfsm:cisco_ios_show_module_online_diag.textfsm, .*, cisco_ios, sh[[ow]] mod[[ule]]
    cisco_ios_show_ip_interface_brief.textfsm, .*, cisco_ios, sh[[ow]] ip int[[erface]] br[[ief]]
    cisco_ios_show_ip_interface.textfsm, .*, cisco_ios, sh[[ow]] ip int[[erface]]
    cisco_ios_show_version.textfsm, .*, cisco_ios, sh[[ow]] ver[[sion]]
    """#

    func testResolvesExactCommandViaCompletionExpansion() throws {
        let index = try TextFSMIndexTable(contents: Self.realIndexSlice)
        XCTAssertEqual(
            try index.template(forPlatform: "cisco_ios", command: "show version"),
            "cisco_ios_show_version.textfsm"
        )
    }

    func testResolvesAbbreviatedCommandViaCompletionExpansion() throws {
        let index = try TextFSMIndexTable(contents: Self.realIndexSlice)
        XCTAssertEqual(
            try index.template(forPlatform: "cisco_ios", command: "sh ver"),
            "cisco_ios_show_version.textfsm"
        )
    }

    /// The real index lists `show_ip_interface_brief` before the shorter
    /// `show_ip_interface` for a reason: `show ip interface` (no "brief")
    /// matches "show ip interface brief" too under re.match's "anchored
    /// at start, not at end" semantics. First-match-wins in file order is
    /// what makes the longer/more specific template win — if this ever
    /// starts picking the wrong template, row ordering broke, not matching.
    func testMoreSpecificCommandWinsOverPrefixMatchDueToFileOrder() throws {
        let index = try TextFSMIndexTable(contents: Self.realIndexSlice)
        XCTAssertEqual(
            try index.template(forPlatform: "cisco_ios", command: "show ip interface brief"),
            "cisco_ios_show_ip_interface_brief.textfsm"
        )
        XCTAssertEqual(
            try index.template(forPlatform: "cisco_ios", command: "show ip interface"),
            "cisco_ios_show_ip_interface.textfsm"
        )
    }

    func testPlatformColumnIsARegexNotALiteralString() throws {
        let index = try TextFSMIndexTable(contents: Self.realIndexSlice)
        XCTAssertEqual(
            try index.template(forPlatform: "cisco_asa", command: "show arp"),
            "cisco_asa_show_arp.textfsm"
        )
        XCTAssertEqual(
            try index.template(forPlatform: "cisco_ftd", command: "show arp"),
            "cisco_asa_show_arp.textfsm"
        )
    }

    func testUnmatchedPlatformThrows() {
        let index = try! TextFSMIndexTable(contents: Self.realIndexSlice)
        XCTAssertThrowsError(try index.template(forPlatform: "juniper_junos", command: "show version"))
    }

    func testMultiTemplateRowIsRejectedExplicitlyRatherThanSilentlyMergedOrDropped() throws {
        let index = try TextFSMIndexTable(contents: Self.realIndexSlice)
        let resolved = try index.template(forPlatform: "cisco_ios", command: "show module")
        XCTAssertTrue(resolved.contains(":"))

        XCTAssertThrowsError(try NativeTextFSMParser.resolveSingleTemplateName(resolved)) { error in
            guard case TextFSMIndexError.multiTemplateRowNotSupported = error else {
                XCTFail("expected multiTemplateRowNotSupported, got \(error)")
                return
            }
        }
    }

    func testExpandCompletionMatchesRealTextFSMFormula() {
        XCTAssertEqual(TextFSMIndexTable.expandCompletion("sh[[ow]] ver[[sion]]"), "sh(o(w)?)? ver(s(i(o(n)?)?)?)?")
        XCTAssertEqual(TextFSMIndexTable.expandCompletion("show vlan"), "show vlan")
    }

    /// End-to-end: NativeTextFSMParser.parse() with platform/command and no
    /// explicit template, resolving through a real on-disk index + template
    /// file via the same NET_TEXTFSM lookup Netmiko itself uses.
    func testNativeTextFSMParserAutoSelectsTemplateFromIndexOnDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftmikoTextFSMIndexTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Self.realIndexSlice.write(to: tempDir.appendingPathComponent("index"), atomically: true, encoding: .utf8)
        let template = #"""
        Value VERSION (\S+)

        Start
          ^Version ${VERSION} -> Record
        """#
        try template.write(
            to: tempDir.appendingPathComponent("cisco_ios_show_version.textfsm"),
            atomically: true,
            encoding: .utf8
        )

        let previousEnv = ProcessInfo.processInfo.environment["NET_TEXTFSM"]
        Self.setEnvironmentVariable("NET_TEXTFSM", tempDir.path)
        defer {
            if let previousEnv {
                Self.setEnvironmentVariable("NET_TEXTFSM", previousEnv)
            } else {
                Self.unsetEnvironmentVariable("NET_TEXTFSM")
            }
        }

        let parser = NativeTextFSMParser()
        let rows = try parser.parse(
            rawOutput: "Version 15.0(2)SE10\n",
            platform: "cisco_ios",
            command: "show version",
            template: nil
        )
        XCTAssertEqual(rows as? [[String: String]], [["VERSION": "15.0(2)SE10"]])
    }

    /// setenv/unsetenv aren't available on Windows (ucrt uses _putenv_s
    /// instead) — same pattern swift-nio's own test suite uses for this.
    private static func setEnvironmentVariable(_ name: String, _ value: String) {
        #if os(Windows)
        _ = _putenv_s(name, value)
        #else
        setenv(name, value, 1)
        #endif
    }

    private static func unsetEnvironmentVariable(_ name: String) {
        #if os(Windows)
        _ = _putenv_s(name, "")
        #else
        unsetenv(name)
        #endif
    }
}
