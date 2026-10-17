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
//  TTPTests.swift
//  SwiftmikoTests
//
//  Every expected value here was independently cross-checked against
//  the real `ttp` Python package's actual output for the same
//  data/template pair (not reverse-engineered from documentation),
//  then adapted from ttp's own page/host-nested result wrapping to
//  this engine's flatter `[[String: Any]]` shape, which is what
//  TTPParserAdapter already contracts for.
//

import XCTest
@testable import Swiftmiko

final class TTPTests: XCTestCase {
    func testFlatMultiLineGroupNoTags() throws {
        let template = try TTPTemplate(templateString: """
        interface {{ interface }}
         switchport mode {{ mode }}
         switchport access vlan {{ access_vlan }}
        """)
        let data = """
        interface Gi0/1
         switchport mode access
         switchport access vlan 10
        interface Gi0/2
         switchport mode trunk
        """
        let rows = TTPExecution.parse(template: template, rawText: data)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["interface"] as? String, "Gi0/1")
        XCTAssertEqual(rows[0]["mode"] as? String, "access")
        XCTAssertEqual(rows[0]["access_vlan"] as? String, "10")
        XCTAssertEqual(rows[1]["interface"] as? String, "Gi0/2")
        XCTAssertEqual(rows[1]["mode"] as? String, "trunk")
        XCTAssertNil(rows[1]["access_vlan"])
    }

    /// Real ttp: re-matching a variable that's already set in the current
    /// record closes it and starts a new one, even without a <group> tag.
    func testReanchorOnDuplicateVariableStartsNewRecord() throws {
        let template = try TTPTemplate(templateString: "name {{ name }} age {{ age }}")
        let data = "name Bob age 10\nname Alice age 20"
        let rows = TTPExecution.parse(template: template, rawText: data)
        XCTAssertEqual(rows as? [[String: String]], [["name": "Bob", "age": "10"], ["name": "Alice", "age": "20"]])
    }

    /// Default (unformatted) {{ var }} is greedy \S+, so the LAST possible
    /// boundary wins when a literal character also appears inside the
    /// value itself (verified against real ttp: x="a/b", y="c").
    func testDefaultVariableIsGreedy() throws {
        let template = try TTPTemplate(templateString: "path {{ x }}/{{ y }}")
        let rows = TTPExecution.parse(template: template, rawText: "path a/b/c")
        XCTAssertEqual(rows as? [[String: String]], [["x": "a/b", "y": "c"]])
    }

    func testOrphraseDigitAndIPFormatters() throws {
        let template = try TTPTemplate(templateString: """
        {{ ip }} {{ count | DIGIT }} desc {{ description | ORPHRASE }}
        """)
        let rows = TTPExecution.parse(template: template, rawText: "10.0.0.1 42 desc a multi word value")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["ip"] as? String, "10.0.0.1")
        XCTAssertEqual(rows[0]["count"] as? String, "42")
        XCTAssertEqual(rows[0]["description"] as? String, "a multi word value")
    }

    /// Real ttp: nested <group> accumulates its own records scoped to the
    /// parent's current record, reset when the parent itself reanchors;
    /// a child that never matched anything for a given parent record is
    /// omitted from that record entirely (not an empty list/dict).
    func testNestedGroupsAttachAndOmitWhenEmpty() throws {
        let template = try TTPTemplate(templateString: """
        <group name="interfaces*">
        interface {{ interface }}
         ip address {{ ip }}
         <group name="neighbors*">
         neighbor {{ neighbor }} remote-as {{ remote_as }}
         </group>
        </group>
        """)
        let data = """
        interface Gi0/1
         ip address 1.1.1.1
        interface Gi0/2
         ip address 2.2.2.2
         neighbor 10.0.0.1 remote-as 100
         neighbor 10.0.0.2 remote-as 200
        """
        let rows = TTPExecution.parse(template: template, rawText: data)
        XCTAssertEqual(rows.count, 1)
        let interfaces = try XCTUnwrap(rows[0]["interfaces"] as? [[String: Any]])
        XCTAssertEqual(interfaces.count, 2)

        XCTAssertEqual(interfaces[0]["interface"] as? String, "Gi0/1")
        XCTAssertNil(interfaces[0]["neighbors"])

        XCTAssertEqual(interfaces[1]["interface"] as? String, "Gi0/2")
        let neighbors = try XCTUnwrap(interfaces[1]["neighbors"] as? [[String: String]])
        XCTAssertEqual(neighbors, [
            ["neighbor": "10.0.0.1", "remote_as": "100"],
            ["neighbor": "10.0.0.2", "remote_as": "200"],
        ])
    }

    /// Real ttp: a group with no "*" collapses to a single dict when it
    /// matches exactly once, but is still a list when it matches more than
    /// once. "*" forces a list even for exactly one match.
    func testStarSuffixForcesListEvenForASingleMatch() throws {
        let noStar = try TTPTemplate(templateString: """
        <group name="device">
        hostname {{ hostname }}
        </group>
        """)
        let singleRow = TTPExecution.parse(template: noStar, rawText: "hostname R1")
        XCTAssertEqual(singleRow[0]["device"] as? [String: String], ["hostname": "R1"])

        let starred = try TTPTemplate(templateString: """
        <group name="device*">
        hostname {{ hostname }}
        </group>
        """)
        let starredRow = TTPExecution.parse(template: starred, rawText: "hostname R1")
        XCTAssertEqual(starredRow[0]["device"] as? [[String: String]], [["hostname": "R1"]])
    }

    /// Root always produces at least one record, even a fully empty one,
    /// when nothing in the input matches anything — verified against real
    /// ttp, which does the same rather than returning an empty array.
    func testNoMatchesStillProducesOneEmptyRootRecord() throws {
        let template = try TTPTemplate(templateString: "switchport mode {{ mode }}")
        let rows = TTPExecution.parse(template: template, rawText: "nonsense line")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isEmpty)
    }

    /// Real ttp requires the ENTIRE line to match (confirmed empirically:
    /// both leading and trailing unmatched text break the match), not a
    /// free substring search.
    func testLineMatchingIsFullLineNotSubstringSearch() throws {
        let template = try TTPTemplate(templateString: "switchport mode {{ mode }}")
        XCTAssertTrue(TTPExecution.parse(template: template, rawText: "XXXswitchport mode trunk")[0].isEmpty)
        XCTAssertTrue(TTPExecution.parse(template: template, rawText: "switchport mode trunk EXTRA")[0].isEmpty)
        XCTAssertEqual(
            TTPExecution.parse(template: template, rawText: "switchport mode trunk") as? [[String: String]],
            [["mode": "trunk"]]
        )
    }

    func testUnsupportedTagThrowsRatherThanSilentlyMisparsing() {
        XCTAssertThrowsError(try TTPTemplate(templateString: "<vars>\nx = 1\n</vars>")) { error in
            guard case TTPParsingError.unsupportedTag("vars") = error else {
                XCTFail("expected unsupportedTag(\"vars\"), got \(error)")
                return
            }
        }
    }

    func testUnsupportedFormatterThrows() {
        XCTAssertThrowsError(try TTPTemplate(templateString: "{{ x | UPPER }}")) { error in
            guard case TTPParsingError.unsupportedFormatter("UPPER") = error else {
                XCTFail("expected unsupportedFormatter(\"UPPER\"), got \(error)")
                return
            }
        }
    }

    func testUnclosedGroupThrows() {
        XCTAssertThrowsError(try TTPTemplate(templateString: "<group name=\"x\">\nfoo {{ bar }}")) { error in
            guard case TTPParsingError.unclosedGroup("x") = error else {
                XCTFail("expected unclosedGroup(\"x\"), got \(error)")
                return
            }
        }
    }

    func testNativeTTPParserReadsTemplateFromDisk() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftmikoTTPTest-\(UUID().uuidString).ttp")
        try "hostname {{ hostname }}".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let rows = try NativeTTPParser().parse(rawOutput: "hostname R1", template: tempFile.path)
        XCTAssertEqual(rows as? [[String: String]], [["hostname": "R1"]])
    }
}
