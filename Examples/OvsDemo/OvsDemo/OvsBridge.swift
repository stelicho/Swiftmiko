// Examples/OvsDemo/OvsBridge.swift
import Foundation
import Swiftmiko

/// A parsed bridge from "ovs-vsctl show" output.
struct OvsBridge: Identifiable {
    let id = UUID()
    let name: String
    let ports: [String]
}

/// Very small parser for "ovs-vsctl show" output, which looks like:
///
///     a3f8e2b1-...
///         Bridge br0
///             Port "eth0"
///                 Interface "eth0"
///             Port br0
///                 Interface br0
///                     type: internal
///         ovs_version: "2.17.0"
///
/// This only extracts bridge names and their direct port names — not
/// the full interface/type detail — enough for a quick topology view.
enum OvsVsctlShowParser {
    static func parse(_ output: String) -> [OvsBridge] {
        var bridges: [OvsBridge] = []
        var currentName: String?
        var currentPorts: [String] = []

        func flush() {
            if let name = currentName {
                bridges.append(OvsBridge(name: name, ports: currentPorts))
            }
            currentName = nil
            currentPorts = []
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("Bridge ") {
                flush()
                currentName = line
                    .replacingOccurrences(of: "Bridge ", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } else if line.hasPrefix("Port ") {
                let port = line
                    .replacingOccurrences(of: "Port ", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                currentPorts.append(port)
            }
        }
        flush()
        return bridges
    }
}
