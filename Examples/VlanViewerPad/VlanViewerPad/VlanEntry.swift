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
//  Examples/VlanViewerPad/VlanEntry.swift

import Foundation
import Swiftmiko

struct VlanEntry: Identifiable {
    let id = UUID()
    let number: Int
    let name: String
    let status: String
    let ports: [String]
}

/// Parses "show vlan brief" output from IOS-XE.
///
/// Typical output:
///   VLAN Name                             Status    Ports
///   ---- -------------------------------- --------- -------------------------------
///   1    default                          active    Gi1/0/1, Gi1/0/2, Gi1/0/3
///   10   Engineering                      active    Gi1/0/4
///   20   Guest                            active
enum VlanBriefParser {
    static func parse(_ output: String) -> [VlanEntry] {
        var entries: [VlanEntry] = []
        var currentPorts: [String] = []
        var pending: (Int, String, String)?

        func flush() {
            if let (num, name, status) = pending {
                entries.append(VlanEntry(number: num, name: name, status: status, ports: currentPorts))
            }
            pending = nil
            currentPorts = []
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("VLAN") || line.hasPrefix("----") { continue }

            // A new VLAN row starts with a number.
            if let firstToken = line.split(separator: " ").first,
               let vlanNum = Int(firstToken) {
                flush()
                let fields = line.split(separator: " ", maxSplits: .max, omittingEmptySubsequences: true)
                let name = fields.count > 1 ? String(fields[1]) : ""
                let status = fields.count > 2 ? String(fields[2]) : ""
                let portsOnThisLine = fields.count > 3
                    ? fields[3...].joined(separator: " ")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    : []
                pending = (vlanNum, name, status)
                currentPorts = portsOnThisLine
            } else {
                // Continuation line — additional ports wrapped from
                // the same VLAN row (IOS-XE wraps long port lists).
                let more = line.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                currentPorts.append(contentsOf: more)
            }
        }
        flush()
        return entries
    }
}
