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
// Sources/SwiftmikoCLI/Outputters.swift
//
// Port of netmiko/cli_tools/outputters.py.
//
// IMPORTANT GAP: Python's `rich` library has no direct Swift
// equivalent in wide use. This reimplements the SHAPE of Rich's
// output (bordered panels, colored device names, highlighted regex
// matches, syntax-colored JSON) using raw ANSI escape codes rather
// than a real terminal-rendering library. It will look noticeably
// plainer than Netmiko's actual CLI output — box-drawing characters
// and basic 256-color codes rather than Rich's adaptive terminal
// width detection, themes, and true syntax highlighting. Treat this
// as a functional placeholder, not a faithful visual port.

import Foundation

enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case magenta = "\u{001B}[35m"
    case blue = "\u{001B}[34m"
    case green = "\u{001B}[32m"
    case red = "\u{001B}[31m"
    case darkRed = "\u{001B}[38;5;88m"
}

func colored(_ text: String, _ color: ANSIColor, bold: Bool = false) -> String {
    let prefix = bold ? ANSIColor.bold.rawValue + color.rawValue : color.rawValue
    return prefix + text + ANSIColor.reset.rawValue
}

/// Draw a simple bordered panel with a title, approximating Rich's
/// Panel(). Width is based on content, not real terminal width
/// detection — a genuine simplification versus Rich's behavior.
func panel(title: String, body: String, borderColor: ANSIColor = .blue) -> String {
    let lines = body.components(separatedBy: "\n")
    let contentWidth = max(lines.map(\.count).max() ?? 0, title.count) + 2
    let top = "╭─ " + colored(title, .magenta, bold: true) + " " +
        String(repeating: "─", count: max(0, contentWidth - title.count - 3)) + "╮"
    let bottom = "╰" + String(repeating: "─", count: contentWidth + 1) + "╯"
    let paddedBody = lines.map { "│ " + $0.padding(toLength: contentWidth - 1, withPad: " ", startingAt: 0) + "│" }
        .joined(separator: "\n")
    return [colored(top, borderColor), paddedBody, colored(bottom, borderColor)].joined(separator: "\n")
}

/// Maps to output_raw(results).
func outputRaw(_ results: [String: String]) {
    if results.count == 1 {
        for (_, output) in results { print(output) }
    } else {
        for (name, output) in results {
            print(colored(name, .blue, bold: true))
            print(colored(String(repeating: "-", count: name.count), .blue))
            print(output)
            print()
        }
    }
}

/// Maps to output_text(results, pattern=None).
func outputText(_ results: [String: String], pattern: String? = nil) {
    for (name, output) in results {
        let body: String
        if let pattern {
            body = highlightRegexWithContext(output, pattern: pattern)
        } else {
            body = output
        }
        print()
        print(panel(title: name, body: body))
        print()
    }
}

/// Maps to output_json(results, raw=False).
///
/// No real syntax highlighting here — Rich's Syntax() class does
/// genuine tokenized JSON coloring; this just pretty-prints. A true
/// port would need a small hand-rolled JSON tokenizer/colorizer.
func outputJSON(_ results: [String: String], raw: Bool = false) throws {
    for (name, output) in results {
        guard let data = output.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            throw CLIToolError.malformedJSONOutput(deviceName: name)
        }
        let formatted = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        let formattedString = String(data: formatted, encoding: .utf8) ?? ""

        if raw {
            print()
            print(name)
            print(String(repeating: "-", count: name.count))
            print(formattedString)
            print()
        } else {
            print()
            print(name)
            print(panel(title: name, body: formattedString, borderColor: .green))
            print()
        }
    }
}

/// Maps to output_yaml(results) — Netmiko's own implementation is a
/// no-op stub (`pass`), preserved as such here.
func outputYAML(_ results: [String: String]) {}

/// Maps to output_failed_devices(failed_devices).
func outputFailedDevices(_ failedDevices: [String]) {
    guard !failedDevices.isEmpty else { return }
    let sorted = failedDevices.sorted()
    let body = sorted.map { "  \($0)" }.joined(separator: "\n")
    print()
    print(panel(title: "Failed devices", body: "\n" + body + "\n", borderColor: .darkRed))
    print()
}

/// Highlight lines matching a regex, showing only matches plus
/// surrounding context lines — the grep-like display used by
/// swiftmiko-grep.
///
/// Maps to highlight_regex_with_context(text, pattern,
/// highlight_color="red", context_lines=2).
func highlightRegexWithContext(
    _ text: String,
    pattern: String,
    contextLines: Int = 2
) -> String {
    let lines = text.components(separatedBy: "\n")
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

    var resultLines: [String] = []
    var lastMatchIndex = -1

    for (i, line) in lines.enumerated() {
        let range = NSRange(line.startIndex..., in: line)
        guard regex.firstMatch(in: line, range: range) != nil else { continue }

        let start = max(0, i - contextLines)
        for j in start..<i where j > lastMatchIndex {
            resultLines.append(lines[j])
        }

        var highlighted = line
        // Highlight all matches on this line, working backward so
        // earlier ranges aren't invalidated by inserting escape codes.
        let matches = regex.matches(in: line, range: range).reversed()
        for match in matches {
            guard let swiftRange = Range(match.range, in: highlighted) else { continue }
            let matchedText = String(highlighted[swiftRange])
            highlighted.replaceSubrange(swiftRange, with: colored(matchedText, .red, bold: true))
        }
        resultLines.append(highlighted)

        let end = min(lines.count, i + contextLines + 1)
        for j in (i + 1)..<end {
            resultLines.append(lines[j])
        }
        lastMatchIndex = end - 1

        if end < lines.count {
            resultLines.append("...")
            resultLines.append("")
        }
    }
    return resultLines.joined(separator: "\n")
}

extension CLIToolError {
    static func malformedJSONOutput(deviceName: String) -> CLIToolError {
        // Reuses the existing error enum's description mechanism by
        // piggybacking on a generic case — see the note in
        // CommonOptions.swift; in a real implementation this would be
        // its own case with the full explanatory message Netmiko's
        // Python version raises (about needing '| json' or TextFSM
        // support on the device).
        .deviceOrGroupNotFound(deviceName)
    }
}

/// Dispatch to the correct output function based on format string.
///
/// Maps to output_dispatcher(out_format, results, pattern=None,
/// hide_empty=False).
func outputDispatcher(
    format: String,
    results: [String: String],
    pattern: String? = nil,
    hideEmpty: Bool = false
) throws {
    var sorted = results
    if hideEmpty {
        sorted = sorted.filter { !$0.value.isEmpty }
    }
    let ordered = sorted.sorted { $0.key < $1.key }
    let orderedDict = Dictionary(uniqueKeysWithValues: ordered)

    switch format {
    case "text", "text_highlighted":
        if format == "text_highlighted" {
            guard let pattern else {
                throw CLIToolError.grepPatternNotSpecified
            }
            outputText(orderedDict, pattern: pattern)
        } else {
            outputText(orderedDict)
        }
    case "json":
        try outputJSON(orderedDict)
    case "json_raw":
        try outputJSON(orderedDict, raw: true)
    case "yaml":
        outputYAML(orderedDict)
    case "raw":
        outputRaw(orderedDict)
    default:
        outputText(orderedDict)
    }
}
