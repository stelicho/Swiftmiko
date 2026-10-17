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
//  TTPExecution.swift
//  Swiftmiko
//
//  Matching engine, verified against the real `ttp` package's actual
//  behavior: a line matching a variable that's already set in the
//  current record closes that record (recursively attaching any
//  pending child-group data first) and starts a new one. Each group
//  (root and every nested <group>) tracks this independently, so
//  reanchoring a parent doesn't disturb a sibling group's own cursor.
//

import Foundation

private final class TTPGroupRuntime {
    var currentRecord: [String: Any] = [:]
    var finishedRecords: [[String: Any]] = []
    var children: [String: TTPGroupRuntime] = [:]

    func descendant(following path: ArraySlice<String>) -> TTPGroupRuntime {
        guard let head = path.first else { return self }
        if children[head] == nil { children[head] = TTPGroupRuntime() }
        return children[head]!.descendant(following: path.dropFirst())
    }

    /// Attaches every child's finished records into this record under the
    /// child's name (list if the group name ended in "*" or it produced
    /// more than one record, a single dict otherwise), omitting children
    /// that never matched anything for this record at all.
    private func attachChildren(forceListByPath: [String: Bool], path: [String]) {
        for (childName, child) in children {
            let childPath = path + [childName]
            child.finalize(forceListByPath: forceListByPath, path: childPath, isRoot: false)
            guard !child.finishedRecords.isEmpty else { continue }
            let forceList = forceListByPath[childPath.joined(separator: "/")] ?? false
            currentRecord[childName] = (forceList || child.finishedRecords.count > 1)
                ? child.finishedRecords
                : child.finishedRecords[0]
        }
        children.removeAll()
    }

    /// Closes out the current record: attaches pending child data, then
    /// pushes it to `finishedRecords`. The root always produces at least
    /// one record (even an entirely empty one, matching real ttp); every
    /// other group is omitted from its parent entirely if it never
    /// captured anything.
    func finalize(forceListByPath: [String: Bool], path: [String], isRoot: Bool) {
        attachChildren(forceListByPath: forceListByPath, path: path)
        if isRoot || !currentRecord.isEmpty {
            finishedRecords.append(currentRecord)
        }
        currentRecord = [:]
    }
}

enum TTPExecution {
    static func parse(template: TTPTemplate, rawText: String) -> [[String: Any]] {
        let root = TTPGroupRuntime()

        for rawLine in rawText.components(separatedBy: .newlines) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            for matcher in template.matchers {
                guard let match = matcher.regex.firstMatch(in: line, range: range) else { continue }

                var captured: [String: String] = [:]
                for (syntheticName, realName) in matcher.nameMapping {
                    let groupRange = match.range(withName: syntheticName)
                    guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: line) else { continue }
                    captured[realName] = String(line[swiftRange])
                }

                let target = root.descendant(following: matcher.groupPath[...])
                let reanchors = captured.keys.contains { target.currentRecord[$0] != nil }
                if reanchors {
                    target.finalize(
                        forceListByPath: template.forceListByPath,
                        path: matcher.groupPath,
                        isRoot: matcher.groupPath.isEmpty
                    )
                }
                for (key, value) in captured {
                    target.currentRecord[key] = value
                }
                break
            }
        }

        root.finalize(forceListByPath: template.forceListByPath, path: [], isRoot: true)
        return root.finishedRecords
    }
}
