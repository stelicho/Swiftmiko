// Examples/PaloAltoDemo/PaloAltoCommand.swift
import Foundation

/// A curated set of read-only PAN-OS operational commands.
struct PaloAltoCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [PaloAltoCommand] = [
        .init(label: "System Info", command: "show system info"),
        .init(label: "Interfaces", command: "show interface all"),
        .init(label: "Session Info", command: "show session info"),
        .init(label: "Routing Table", command: "show routing route"),
        .init(label: "HA State", command: "show high-availability state"),
        .init(label: "Running Config (set format)", command: "show config running"),
    ]
}
