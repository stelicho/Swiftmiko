// Examples/JuniperDemo/JuniperCommand.swift
import Foundation

/// A curated set of read-only JunOS operational commands, useful for
/// smoke-testing JuniperSSH without typing anything.
struct JuniperCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [JuniperCommand] = [
        .init(label: "Version", command: "show version"),
        .init(label: "Interfaces Terse", command: "show interfaces terse"),
        .init(label: "Configuration", command: "show configuration"),
        .init(label: "Route Summary", command: "show route summary"),
        .init(label: "Chassis Hardware", command: "show chassis hardware"),
        .init(label: "System Uptime", command: "show system uptime"),
    ]
}
