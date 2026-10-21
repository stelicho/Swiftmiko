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
// Tests/SwiftmikoCLITests/OutputtersTests.swift
//
// Coverage for highlightRegexWithContext() and panel() — previously
// untested despite having real, non-trivial logic: context-window
// math, a lastMatchIndex dedup guard against re-printing lines two
// nearby matches both want as context, backward-iterated per-line
// multi-match highlighting (so inserting ANSI codes doesn't invalidate
// later match ranges), and panel()'s content-width/padding math. Every
// expected string below was independently confirmed by running the
// real function against each scenario first (not hand-derived), so
// these pin down actual current behavior rather than an assumed spec.

import XCTest
@testable import SwiftmikoCLI

final class OutputtersTests: XCTestCase {

    // MARK: - highlightRegexWithContext

    func testSingleMatchIncludesSurroundingContextAndTrailingTruncationMarker() {
        let text = ["line0", "line1", "line2", "MATCH", "line4", "line5", "line6"]
            .joined(separator: "\n")
        let result = highlightRegexWithContext(text, pattern: "MATCH")

        let expected = [
            "line1", "line2",
            colored("MATCH", .red, bold: true),
            "line4", "line5",
            "...", "",
        ].joined(separator: "\n")

        XCTAssertEqual(result, expected)
    }

    func testMatchNearStartClampsLeadingContextToZeroInsteadOfUnderflowing() {
        let text = ["MATCH", "line1", "line2", "line3"].joined(separator: "\n")
        let result = highlightRegexWithContext(text, pattern: "MATCH")

        // start = max(0, 0 - 2) must clamp to 0, not go negative — if it
        // didn't, this would crash or behave differently rather than
        // just omitting the (nonexistent) lines before the match.
        let expected = [
            colored("MATCH", .red, bold: true),
            "line1", "line2",
            "...", "",
        ].joined(separator: "\n")

        XCTAssertEqual(result, expected)
    }

    func testMatchAtEndOfTextOmitsTheTruncationMarker() {
        let text = ["line0", "line1", "line2", "MATCH"].joined(separator: "\n")
        let result = highlightRegexWithContext(text, pattern: "MATCH")

        // The match's trailing context window reaches exactly the end
        // of the text (end == lines.count), so the "end < lines.count"
        // guard must suppress the "..." marker and the blank line after
        // it — there's nothing left being truncated.
        let expected = [
            "line1", "line2",
            colored("MATCH", .red, bold: true),
        ].joined(separator: "\n")

        XCTAssertEqual(result, expected)
    }

    func testTwoNearbyMatchesDoNotDuplicateContextLinesAlreadyShown() {
        let text = ["a0", "MATCH1", "a2", "a3", "MATCH2", "a5", "a6"].joined(separator: "\n")
        let result = highlightRegexWithContext(text, pattern: "MATCH")

        // MATCH2's own leading-context window (lines 2-3) was already
        // printed as MATCH1's trailing context — the lastMatchIndex
        // guard must skip re-printing "a2"/"a3" a second time.
        let expected = [
            "a0",
            colored("MATCH", .red, bold: true) + "1",
            "a2", "a3",
            "...", "",
            colored("MATCH", .red, bold: true) + "2",
            "a5", "a6",
        ].joined(separator: "\n")

        XCTAssertEqual(result, expected)
    }

    func testHighlightsEveryMatchOnTheSameLineNotJustTheFirst() {
        // Also exercises the backward (reversed) match iteration: if
        // earlier ranges were invalidated by inserting ANSI codes for a
        // later match first, this would come out garbled or miss matches.
        let result = highlightRegexWithContext("banana", pattern: "a")

        let a = colored("a", .red, bold: true)
        XCTAssertEqual(result, "b\(a)n\(a)n\(a)")
    }

    func testReturnsEmptyStringWhenNothingMatches() {
        let text = ["x", "y", "z"].joined(separator: "\n")
        XCTAssertEqual(highlightRegexWithContext(text, pattern: "ZZZ"), "")
    }

    func testInvalidRegexPatternReturnsOriginalTextUnchanged() {
        let text = ["x", "y", "z"].joined(separator: "\n")
        XCTAssertEqual(highlightRegexWithContext(text, pattern: "(unclosed"), text)
    }

    // MARK: - panel

    func testPanelPadsBodyToContentWidthAndFramesTheTitle() {
        let result = SwiftmikoCLI.panel(title: "Host", body: "short")

        // contentWidth = max("short".count, "Host".count) + 2 = 7.
        // Top-border dash count = max(0, contentWidth - title.count - 3) = 0.
        let top = colored(
            "╭─ " + colored("Host", .magenta, bold: true) + " ╮",
            .blue
        )
        let bottom = colored("╰" + String(repeating: "─", count: 8) + "╯", .blue)
        let body = "│ " + "short".padding(toLength: 6, withPad: " ", startingAt: 0) + "│"

        XCTAssertEqual(result, [top, body, bottom].joined(separator: "\n"))
    }

    func testPanelWidensToFitATitleLongerThanTheBody() {
        let title = "A Very Long Title Indeed"
        let result = SwiftmikoCLI.panel(title: title, body: "hi")

        // contentWidth = max(2, 24) + 2 = 26. Dash count would go
        // negative (26 - 24 - 3 = -1) without the max(0, ...) clamp.
        let top = colored(
            "╭─ " + colored(title, .magenta, bold: true) + " ╮",
            .blue
        )
        let bottom = colored("╰" + String(repeating: "─", count: 27) + "╯", .blue)
        let body = "│ " + "hi".padding(toLength: 25, withPad: " ", startingAt: 0) + "│"

        XCTAssertEqual(result, [top, body, bottom].joined(separator: "\n"))
    }

    func testPanelPadsEachLineOfAMultilineBodyIndependentlyToTheSameWidth() {
        let result = SwiftmikoCLI.panel(title: "T", body: "line1\nlonger line two")

        // contentWidth = max("longer line two".count = 15, "T".count = 1) + 2 = 17.
        let top = colored(
            "╭─ " + colored("T", .magenta, bold: true) + " " +
                String(repeating: "─", count: 13) + "╮",
            .blue
        )
        let bottom = colored("╰" + String(repeating: "─", count: 18) + "╯", .blue)
        let line1 = "│ " + "line1".padding(toLength: 16, withPad: " ", startingAt: 0) + "│"
        let line2 = "│ " + "longer line two".padding(toLength: 16, withPad: " ", startingAt: 0) + "│"

        XCTAssertEqual(result, [top, line1, line2, bottom].joined(separator: "\n"))
    }
}
