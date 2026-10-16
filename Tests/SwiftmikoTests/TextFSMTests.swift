// Tests/SwiftmikoTests/TextFSMTests.swift
//
// Coverage for the native TextFSM engine (Sources/TextFSM/). Exercises
// the parts of the grammar that are easy to get subtly wrong — option
// interactions, ICU's rejection of underscored named groups (which real
// Value names routinely use), and the exact Required/List/Filldown/
// Clear/Clearall semantics — plus a full run against a real, unmodified
// ntc-templates file to guard against "looks right in isolation but
// doesn't actually parse real output" regressions.

import XCTest
@testable import Swiftmiko

final class TextFSMTests: XCTestCase {
    func testBasicValueAndRuleParsing() throws {
        let template = try TextFSMTemplate(templateString: """
        Value NAME (\\S+)
        Value AGE (\\d+)

        Start
          ^Name:\\s+${NAME}\\s+Age:\\s+${AGE} -> Record
        """)

        let rows = try template.parseTextToDicts("""
        Name: Alice   Age: 30
        Name: Bob   Age: 25
        """)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["NAME"] as? String, "Alice")
        XCTAssertEqual(rows[0]["AGE"] as? String, "30")
        XCTAssertEqual(rows[1]["NAME"] as? String, "Bob")
        XCTAssertEqual(template.header, ["NAME", "AGE"])
    }

    /// NSRegularExpression's named capture groups only accept
    /// [A-Za-z][A-Za-z0-9]* — no underscores — while real TextFSM value
    /// names (VLAN_ID, INTERFACE_NAME, ...) routinely have them. This
    /// guards the sanitize/restore layer that makes that transparent.
    func testUnderscoredValueNamesSurviveIntactInOutput() throws {
        let template = try TextFSMTemplate(templateString: """
        Value VLAN_ID (\\d+)
        Value INTERFACE_NAME (\\S+)

        Start
          ^${VLAN_ID}\\s+${INTERFACE_NAME} -> Record
        """)

        let rows = try template.parseTextToDicts("10 Gi1/0/1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["VLAN_ID"] as? String, "10")
        XCTAssertEqual(rows[0]["INTERFACE_NAME"] as? String, "Gi1/0/1")
    }

    func testListAccumulatesPlainStrings() throws {
        let template = try TextFSMTemplate(templateString: """
        Value List SERIAL (\\w+)

        Start
          ^Serial:\\s+${SERIAL}
        """)

        let rows = try template.parseTextToDicts("""
        Serial: ABC123
        Serial: DEF456
        """)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["SERIAL"] as? [String], ["ABC123", "DEF456"])
    }

    /// A List value whose own regex has NAMED nested groups should
    /// collect dictionaries, not plain strings.
    func testListWithNestedNamedGroupsCollectsDictionaries() throws {
        let template = try TextFSMTemplate(templateString: """
        Value List INTERFACE_INFO ((?P<if_name>\\S+)\\s+(?P<if_status>up|down))

        Start
          ^\\s+${INTERFACE_INFO}\\s*$$
        """)

        let rows = try template.parseTextToDicts("""
          eth0 up
          eth1 down
        """)

        XCTAssertEqual(rows.count, 1)
        let entries = try XCTUnwrap(rows[0]["INTERFACE_INFO"] as? [[String: String]])
        XCTAssertEqual(entries, [
            ["if_name": "eth0", "if_status": "up"],
            ["if_name": "eth1", "if_status": "down"],
        ])
    }

    /// A List value with an unnamed nested group (common in real
    /// templates, e.g. a repeated `(:[0-9a-f]{2})` inside a MAC address
    /// pattern) must still collect plain strings — Python's own
    /// `match.groupdict()` is empty for unnamed groups, so it falls back
    /// to the raw text rather than an empty dict.
    func testListWithUnnamedNestedGroupFallsBackToPlainStrings() throws {
        let template = try TextFSMTemplate(templateString: """
        Value List MAC_ADDRESS ([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5})

        Start
          ^MAC:\\s+${MAC_ADDRESS}
        """)

        let rows = try template.parseTextToDicts("MAC: 00:1A:2B:3C:4D:5E")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["MAC_ADDRESS"] as? [String], ["00:1A:2B:3C:4D:5E"])
    }

    /// Filldown persists a value across Clear (the "soft" reset after a
    /// Record), but Clearall wipes the saved state too.
    func testFilldownSurvivesClearButNotClearall() throws {
        let template = try TextFSMTemplate(templateString: """
        Value A (\\d+)
        Value Filldown B (\\d+)

        Start
          ^A=${A}$$ -> Continue
          ^B=${B}$$ -> Continue
          ^RECORD$$ -> Record
          ^CLEAR$$ -> Clear
          ^CLEARALL$$ -> Clearall
        """)

        let clearRows = try template.parseTextToDicts("A=1\nB=2\nRECORD\nCLEAR\nRECORD\n")
        XCTAssertEqual(clearRows[0]["A"] as? String, "1")
        XCTAssertEqual(clearRows[0]["B"] as? String, "2")
        XCTAssertEqual(clearRows[1]["A"] as? String, "", "A has no Filldown, so Clear wipes it")
        XCTAssertEqual(clearRows[1]["B"] as? String, "2", "B is Filldown, so it survives Clear")

        let clearallRows = try template.parseTextToDicts("A=1\nB=2\nRECORD\nCLEARALL\nRECORD\n")
        XCTAssertEqual(clearallRows[1]["B"] as? String, "", "Clearall wipes Filldown's saved state too")
    }

    /// `Required` drops the whole record (silently, not an error) when
    /// that value is still empty at Record time.
    func testRequiredDropsRecordWhenEmpty() throws {
        let template = try TextFSMTemplate(templateString: """
        Value Required NAME (\\S+)
        Value AGE (\\d+)

        Start
          ^Name:\\s+${NAME} -> Continue
          ^Name:\\s+${NAME}\\s+Age:\\s+${AGE} -> Record
          ^NoName$$ -> Record
        """)

        let rows = try template.parseTextToDicts("Name: Alice Age: 30\nNoName\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["NAME"] as? String, "Alice")
    }

    /// An `Error` rule firing against real input throws, carrying the
    /// template-defined message and the offending input line.
    func testErrorRuleThrows() throws {
        let template = try TextFSMTemplate(templateString: """
        Value A (\\d+)

        Start
          ^A=${A}
          ^BOOM -> Error "boom happened"
        """)

        XCTAssertThrowsError(try template.parseTextToDicts("BOOM\n")) { error in
            guard case TextFSMRuntimeError.templateDefinedError(let message, _, let inputLine) = error else {
                XCTFail("Expected templateDefinedError, got \(error)")
                return
            }
            XCTAssertEqual(message, "boom happened")
            XCTAssertEqual(inputLine, "BOOM")
        }
    }

    func testMissingStartStateIsRejected() {
        XCTAssertThrowsError(try TextFSMTemplate(templateString: """
        Value A (\\d+)

        NotStart
          ^A=${A} -> Record
        """)) { error in
            guard case TextFSMTemplateError.missingStartState = error else {
                XCTFail("Expected missingStartState, got \(error)")
                return
            }
        }
    }

    func testUnknownNewStateIsRejected() {
        XCTAssertThrowsError(try TextFSMTemplate(templateString: """
        Value A (\\d+)

        Start
          ^A=${A} -> Nowhere
        """)) { error in
            guard case TextFSMTemplateError.unknownNewState = error else {
                XCTFail("Expected unknownNewState, got \(error)")
                return
            }
        }
    }

    /// Full run against a real, completely unmodified ntc-templates file
    /// (networktocode/ntc-templates: cisco_ios_show_version.textfsm) —
    /// the actual point of a native engine is working against the real
    /// template corpus, not a simplified Swiftmiko-specific dialect.
    func testRealCiscoIOSShowVersionTemplate() throws {
        let template = try TextFSMTemplate(templateString: Self.ciscoIOSShowVersionTemplate)

        let output = """
        Cisco IOS Software, C3750 Software (C3750-IPSERVICESK9-M), Version 15.0(2)SE10, RELEASE SOFTWARE (fc3)
        Technical Support: http://www.cisco.com/techsupport
        Copyright (c) 1986-2017 by Cisco Systems, Inc.
        Compiled Thu 20-Jul-17 02:21 by prod_rel_team

        ROM: Bootstrap program is C3750 boot loader

        switch3 uptime is 1 year, 2 weeks, 3 days, 4 hours, 5 minutes
        System returned to ROM by power-on
        System image file is "flash:/c3750-ipservicesk9-mz.150-2.SE10/c3750-ipservicesk9-mz.150-2.SE10.bin"

        cisco WS-C3750G-24TS-1U (PowerPC405) processor (revision H0) with 131072K bytes of memory.
        Processor board ID CAT1234A5BC
        Base ethernet MAC Address       : 00:1A:2B:3C:4D:5E

        Configuration register is 0xF
        """

        let rows = try template.parseTextToDicts(output)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]

        XCTAssertEqual(row["SOFTWARE_IMAGE"] as? String, "C3750-IPSERVICESK9-M")
        XCTAssertEqual(row["VERSION"] as? String, "15.0(2)SE10")
        XCTAssertEqual(row["RELEASE"] as? String, "fc3")
        XCTAssertEqual(row["HOSTNAME"] as? String, "switch3")
        XCTAssertEqual(row["UPTIME_YEARS"] as? String, "1")
        XCTAssertEqual(row["UPTIME_WEEKS"] as? String, "2")
        XCTAssertEqual(row["UPTIME_DAYS"] as? String, "3")
        XCTAssertEqual(row["UPTIME_HOURS"] as? String, "4")
        XCTAssertEqual(row["UPTIME_MINUTES"] as? String, "5")
        XCTAssertEqual(row["RELOAD_REASON"] as? String, "power-on")
        XCTAssertEqual(row["CONFIG_REGISTER"] as? String, "0xF")
        XCTAssertEqual(row["HARDWARE"] as? [String], ["WS-C3750G-24TS-1U"])
        XCTAssertEqual(row["SERIAL"] as? [String], ["CAT1234A5BC"])
        // Unnamed nested group inside MAC_ADDRESS's own pattern -- must
        // stay a plain string, not an (empty) dictionary.
        XCTAssertEqual(row["MAC_ADDRESS"] as? [String], ["00:1A:2B:3C:4D:5E"])
    }

    /// Verbatim from github.com/networktocode/ntc-templates
    /// (ntc_templates/templates/cisco_ios_show_version.textfsm) —
    /// unmodified, including its comments and the trailing "Stack" state.
    private static let ciscoIOSShowVersionTemplate = #"""
    Value SOFTWARE_IMAGE (\S+)
    Value VERSION (.+?)
    Value RELEASE (\S+)
    Value ROMMON (\S+)
    Value HOSTNAME (\S+)
    Value UPTIME (.+)
    Value UPTIME_YEARS (\d+)
    Value UPTIME_WEEKS (\d+)
    Value UPTIME_DAYS (\d+)
    Value UPTIME_HOURS (\d+)
    Value UPTIME_MINUTES (\d+)
    Value RELOAD_REASON (.+?)
    Value RUNNING_IMAGE (\S+)
    Value List HARDWARE (\S+|\S+\d\S+)
    Value List SERIAL (\w+)
    Value CONFIG_REGISTER (\S+)
    Value List MAC_ADDRESS ([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5})
    Value RESTARTED (.+)

    Start
      ^.*Software,*\s+\(${SOFTWARE_IMAGE}\),\sVersion\s${VERSION},*\s+RELEASE.*\(${RELEASE}\)
      # CUST-SPECIAL:
      ^.*Software,*\s+\(${SOFTWARE_IMAGE}\),\sVersion\s${VERSION},*\s+\S+.*:${RELEASE}
      ^.*Software,*\s+\(${SOFTWARE_IMAGE}\),\sVersion\s${VERSION},
      ^ROM:\s+${ROMMON}
      ^\s*${HOSTNAME}\s+uptime\s+is\s+${UPTIME} -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_YEARS}\syear -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_WEEKS}\sweek -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_DAYS}\sday -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_HOURS}\shour -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_MINUTES}\sminute
      ^[sS]ystem\s+image\s+file\s+is\s+"(.*?):${RUNNING_IMAGE}"
      ^(?:[lL]ast\s+reload\s+reason:|System\s+returned\s+to\s+ROM\s+by)\s+${RELOAD_REASON}\s*$$
      ^[Pp]rocessor\s+board\s+ID\s+${SERIAL}
      ^[Cc]isco\s+${HARDWARE}\s+\(.+\).+
      ^[Cc]onfiguration\s+register\s+is\s+${CONFIG_REGISTER}
      ^Base\s+[Ee]thernet\s+MAC\s+[Aa]ddress\s+:\s+${MAC_ADDRESS}
      ^System\s+restarted\s+at\s+${RESTARTED}$$
      ^Switch\s+Port -> Stack
      # Capture time-stamp if vty line has command time-stamping turned on
      ^Switch\s\d+ -> Stack
      ^Load\s+for\s+
      ^Time\s+source\s+is


    Stack
      ^[Ss]ystem\s+[Ss]erial\s+[Nn]umber\s+:\s+${SERIAL}
      ^[Mm]odel\s+[Nn]umber\s+:\s+${HARDWARE}\s*
      ^[Cc]onfiguration\s+register\s+is\s+${CONFIG_REGISTER}
      ^Base [Ee]thernet MAC [Aa]ddress\s+:\s+${MAC_ADDRESS}
    """#
}
