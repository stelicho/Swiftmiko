// Examples/NokiaDemo/NokiaCommand.swift
import Foundation

/// A curated set of read-only SR OS show commands. These happen to be
/// valid on both CLI dialects (classical and model-driven), unlike the
/// config/commit workflow below, which only does anything real on the
/// model-driven dialect.
struct NokiaCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [NokiaCommand] = [
        .init(label: "Version", command: "show version"),
        .init(label: "System Information", command: "show system information"),
        .init(label: "Port Status", command: "show port"),
        .init(label: "Router Interfaces", command: "show router interface"),
        .init(label: "Uptime", command: "show system uptime"),
    ]
}
